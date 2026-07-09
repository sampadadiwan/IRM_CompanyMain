#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# TODO
# 1. Restore from specific full & specific incremental, ensure the incremental is after full and allow for nil incr backups (i.e restore from full only)
# 2. [DONE — handled outside this script] Backup retention is enforced by S3
#    lifecycle rules on the backup buckets (90d expiry, set idempotently by
#    rake aws:provision_s3_buckets), so no script-side S3 cleanup is needed.
# 3. Check if there is a way to do incr without downloading the full backup
# If not then no need to delete the full backup dir, during the day, reuse for every hourly incr

# This script is baked into the DB-Redis-ES AMI (see db_redis_es.ami.pkr.hcl)
# together with /etc/cron.d/irm-db-backup (nightly full at 23:00, incrementals
# every 30 min). The baked copy contains NO secrets — configuration is resolved
# at runtime (see below). The legacy path still works: rake
# xtrabackup:generate_backup_script substitutes the __PLACEHOLDER__ values for
# a manually installed copy.

# ---------------------------------------------------------------------------
# Configuration resolution, in order:
#   1. Values substituted into this file by generate_backup_script (legacy)
#   2. /etc/db_backup.env — non-secret settings baked by Packer (SSM_PREFIX)
#      and/or operator overrides (root-owned, 0600)
#   3. SSM Parameter Store under $SSM_PREFIX/* — secrets, read at runtime via
#      the EC2 instance role (no credentials on disk)
# AWS access for xbcloud/aws: if no keys are configured, both fall back to the
# default credential chain, i.e. the EC2 instance profile — the preferred mode.
# ---------------------------------------------------------------------------
# SINGLE quotes, deliberately: these values are substituted verbatim by
# generate_backup_script, and credentials can contain $ ` \ which double
# quotes would shell-expand at run time (silent auth failures mid-DR).
BUCKET='__BUCKET__'
AWS_REGION='__AWS_REGION__'
AWS_ACCESS_KEY_ID='__AWS_ACCESS_KEY_ID__'
AWS_SECRET_ACCESS_KEY='__AWS_SECRET_ACCESS_KEY__'
MYSQL_PASSWORD='__MYSQL_PASSWORD__'
MYSQL_USER='__MYSQL_USER__'
DATABASE_NAME='__DATABASE_NAME__'

# In the baked AMI the placeholders are unsubstituted — treat them as unset so
# the env-file/SSM lookups below take over.
for _v in BUCKET AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY MYSQL_PASSWORD MYSQL_USER DATABASE_NAME; do
  if [[ "${!_v}" == __*__ ]]; then unset "$_v"; fi
done

# Non-secret baked config (SSM_PREFIX) and optional operator overrides.
if [[ -f /etc/db_backup.env ]]; then
  # shellcheck disable=SC1091
  source /etc/db_backup.env
fi

# The instance's own region via IMDSv2 — where the SSM parameters live. Note
# this can differ from AWS_REGION, which is the region of the S3 BACKUP BUCKET.
instance_region() {
  local token
  token=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  curl -sf -H "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/placement/region"
}

# Read one parameter from SSM under $SSM_PREFIX (SecureStrings decrypted via
# the instance role). Returns empty on failure so callers can :?-check later.
ssm_get() {
  aws ssm get-parameter --name "${SSM_PREFIX}/$1" --with-decryption \
    --query 'Parameter.Value' --output text --region "$(instance_region)" 2>/dev/null
}

# Fill anything still missing from SSM (seeded by rake xtrabackup:seed_ssm_params).
if [[ -n "${SSM_PREFIX:-}" ]]; then
  : "${BUCKET:=$(ssm_get bucket || true)}"
  : "${AWS_REGION:=$(ssm_get bucket_region || true)}"
  : "${MYSQL_USER:=$(ssm_get mysql_user || true)}"
  : "${MYSQL_PASSWORD:=$(ssm_get mysql_password || true)}"
  : "${DATABASE_NAME:=$(ssm_get database_name || true)}"
fi
# Explicit overrides — HIGHEST priority, applied after all other resolution.
# Lets a restore pull from a non-default bucket, e.g. the DR-region replica
# when the primary region's S3 is unreachable (true region loss):
#   sudo env BUCKET_OVERRIDE=docs.altx.com.staging-replica-backup-xtra \
#            AWS_REGION_OVERRIDE=ap-south-2 \
#        /usr/local/bin/db_backup_xtra.sh restore_primary
BUCKET="${BUCKET_OVERRIDE:-${BUCKET:-}}"
AWS_REGION="${AWS_REGION_OVERRIDE:-${AWS_REGION:-}}"

export BUCKET AWS_REGION MYSQL_PASSWORD MYSQL_USER DATABASE_NAME

# Required config — AWS keys are deliberately NOT required (instance role is
# the preferred auth); everything else must have resolved by now.
: "${AWS_REGION:?not resolved — set in /etc/db_backup.env or SSM ${SSM_PREFIX:-<SSM_PREFIX unset>}/bucket_region}"
: "${BUCKET:?not resolved — set in /etc/db_backup.env or SSM ${SSM_PREFIX:-<SSM_PREFIX unset>}/bucket}"
: "${DATABASE_NAME:?not resolved}"
: "${MYSQL_USER:?not resolved}"
: "${MYSQL_PASSWORD:?not resolved}"
: "${MYSQL_HOST:=localhost}"
: "${MYSQL_PORT:=3306}"

# Backups run only on the armed host — the real primary. The marker is created
# by a successful restore_primary (or manually: sudo touch). Replicas and the
# DbCheckInstance are never armed, so only one writer feeds the backup chain.
ARMED_MARKER="/etc/db_backup_enabled"

MYSQL_TMPDIR="${MYSQL_TMPDIR:-/tmp}"

# Store LSN checkpoints outside /tmp so they survive a server reboot.
# /tmp is cleared on reboot, which would cause incr_backup to lose its starting
# LSN and fall back to downloading the full backup from S3 unnecessarily.
LSNDIR="/var/lib/xtrabackup/lsndir"
LSNDIR_INCR="/var/lib/xtrabackup/lsndir-incr"

export AWS_REGION MYSQL_PWD="$MYSQL_PASSWORD"

XB_ARGS=(--storage=S3
         --s3-bucket="${BUCKET}"
         --s3-region="${AWS_REGION}"
         --s3-endpoint="s3.${AWS_REGION}.amazonaws.com"
         --max-retries=5 --max-backoff=120000 --parallel=4)

# Pass explicit keys only when configured (legacy generated script); otherwise
# xbcloud uses the default AWS credential chain — i.e. the instance profile.
if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  XB_ARGS+=(--s3-access-key="${AWS_ACCESS_KEY_ID}" --s3-secret-key="${AWS_SECRET_ACCESS_KEY}")
fi

TIMESTAMP="$(date +%F_%H%M%S)"
FULL_NAME="${TIMESTAMP}-full"
INCR_NAME="${TIMESTAMP}-incr"
TMPDIR="${MYSQL_TMPDIR}/xb_$$"
STAGING_FULL="${TMPDIR}/staging_full"
TEST_RESTORE="${TMPDIR}/test_restore"
PRIMARY_RESTORE="${TMPDIR}/primary_restore"

mkdir -p "$TMPDIR"

retry() {
  local max=$1; shift; local cmd=("$@"); local n=0
  until "${cmd[@]}"; do
    ((n++)) || :
    if (( n >= max )); then
      echo "ERROR: '${cmd[*]}' failed after $n attempts" >&2; return 1
    fi
    echo "WARN: '${cmd[*]}' failed – retry $n/$max" >&2
    sleep $((n * 5))
  done
}

# Notifies on any unhandled script error. Set NOTIFY_WEBHOOK_URL in the environment
# to receive alerts (Slack, PagerDuty, etc.) in addition to stderr logging.
notify_failure() {
  echo "ERROR: backup script failed at line $1 (command: $2)" >&2
  if [[ -n "${NOTIFY_WEBHOOK_URL:-}" ]]; then
    curl -s --max-time 10 -X POST "$NOTIFY_WEBHOOK_URL" \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"DB Backup FAILED on $(hostname) at line $1\"}" || true
  fi
}
trap 'notify_failure "$LINENO" "$BASH_COMMAND"' ERR

# 1. Stream & prepare the full backup
restore_full() {
  local key=$1 dir=$2
  echo "→ Restoring full backup '$key' to $dir"
  rm -rf "$dir" && mkdir -p "$dir"
  # Download and extract the full backup from S3.
  # Note: The user running this script needs permissions to run xbcloud
  # and write to the target directory. 'sudo' was removed to avoid
  # assuming root privileges are available or necessary.
  retry 3 xbcloud "${XB_ARGS[@]}" get "$key" | xbstream -x -C "$dir"

  # Decompress the backup files. This is required if the backup was compressed.
  xtrabackup --decompress --target-dir="$dir"

  # Prepare the full backup. --apply-log-only is used because
  # incremental backups will be applied on top of this.
  xtrabackup --prepare --apply-log-only --target-dir="$dir"
}

# 2. Stream & apply an incremental onto staging
apply_incremental() {
  local key=$1 dir=$2
  local incr_tmp_dir="${TMPDIR}/incr_stage_$$"
  echo "→ Applying incremental '$key' → $dir (using temp dir $incr_tmp_dir)"

  # Create a temporary directory for the incremental backup
  rm -rf "$incr_tmp_dir" && mkdir -p "$incr_tmp_dir"

  # Download and extract the incremental backup into its own temporary directory
  # to avoid file conflicts with the base backup.
  retry 3 xbcloud "${XB_ARGS[@]}" get "$key" \
    | xbstream -x -C "$incr_tmp_dir"

  # Decompress the incremental backup files.
  xtrabackup --decompress --target-dir="$incr_tmp_dir"

  # Apply the incremental logs to the staging directory using --incremental-dir.
  # This is the correct way to merge the delta files.
  # --apply-log-only is crucial here as we might apply more incrementals.
  xtrabackup --prepare --apply-log-only --target-dir="$dir" --incremental-dir="$incr_tmp_dir"

  # Clean up the temporary incremental directory
  rm -rf "$incr_tmp_dir"
}




# 3. Final prepare (no apply-log-only)
final_prepare() {
  echo "→ Final prepare staging → $1"
  xtrabackup --prepare --target-dir="$1"
}

get_all_incrs() {
  aws s3api list-objects-v2 --bucket "$BUCKET" --delimiter '/' \
    --query "CommonPrefixes[?ends_with(Prefix,'-incr/')].Prefix | sort(@)" \
    --output text | tr '\t' '\n' | sed 's!/$!!'
}

get_all_incrs_since_full() {
  local full_key=$1
  get_all_incrs | while read -r incr_key; do
    # The sort in get_all_incrs is lexical, which is correct for the timestamp format YYYY-MM-DD_HHMMSS
    if [[ "$incr_key" > "$full_key" ]]; then
      echo "$incr_key"
    fi
  done
}

get_latest_full() {
  aws s3api list-objects-v2 \
    --bucket "$BUCKET" \
    --delimiter '/' \
    --query "CommonPrefixes[?ends_with(Prefix, '-full/')].Prefix" \
    --output text |
    tr '\t' '\n' |
    sed 's!/$!!' |
    sort -V |
    tail -n1
}

restore_latest_chain() {
  local full_key
  full_key=$(get_latest_full)
  if [[ -z "$full_key" ]]; then
    echo "ERROR: No full backup found." >&2
    return 1
  fi
  echo "Found latest full backup: $full_key"

  local all_incrs=()
  # Read all incremental backups since the full backup into the all_incrs array.
  # The `mapfile` command (an alias for `readarray`) reads lines from standard
  # input into an array variable. This is a robust way to handle command output.
  mapfile -t all_incrs < <(get_all_incrs_since_full "$full_key")

  local incr_chain=()
  if (( ${#all_incrs[@]} > 0 )); then
    # Use only the last incremental backup
    incr_chain+=("${all_incrs[-1]}")
    echo "Found latest incremental backup to apply:"
    printf "  - %s\n" "${incr_chain[@]}"
  else
    echo "No incremental backups found to apply."
  fi

  prepare_restore_from_keys "$full_key" "${incr_chain[@]}"
}

prepare_restore_from_keys() {
  local full_key=$1
  shift
  local incr_chain=("$@")

  echo "========================================================================"
  echo "              RESTORING FROM THE FOLLOWING BACKUPS"
  echo "========================================================================"
  echo
  printf "  %-15s %s\n" "TYPE" "KEY"
  printf "  %-15s %s\n" "---------------" "--------------------------------------------------"
  printf "  %-15s %s\n" "FULL" "$full_key"

  if (( ${#incr_chain[@]} > 0 )); then
    for incr in "${incr_chain[@]}"; do
      if [[ -n "$incr" ]]; then
        printf "  %-15s %s\n" "INCREMENTAL" "$incr"
      fi
    done
  else
    echo
    echo "  No incremental backups found to apply for this full backup."
  fi
  echo
  echo "========================================================================"

  # 1. Restore full backup directly into the staging directory.
  restore_full "$full_key" "$STAGING_FULL"

  # 2. Apply all incrementals in the chain
  if (( ${#incr_chain[@]} > 0 )); then
    for incr_key in "${incr_chain[@]}"; do
      if [[ -n "$incr_key" ]]; then
        apply_incremental "$incr_key" "$STAGING_FULL"
      fi
    done
  fi

  # 4. Final prepare on the staged backup
  final_prepare "$STAGING_FULL"

  # 5. Copy prepared backup to final restore directory
  echo "→ Copying prepared backup to final restore directory"
  local restore_to_primary="$PRIMARY_RESTORE"
  rm -rf "$restore_to_primary" && mv "$STAGING_FULL" "$restore_to_primary"
  echo "Restore chain complete. Data is in $restore_to_primary"
}

get_table_counts() {
  local db_name=$1
  local user=$2
  local sock_arg=""
  # Use a socket if provided (for test instances)
  if [[ -n "${3:-}" ]]; then
    sock_arg="--socket=$3"
  fi

  echo "→ Getting table counts for database '$db_name'..."

  # Get all table names from the specified database.
  local tables
  tables=$(mysql --user="$user" $sock_arg -sN -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '${db_name}';")

  if [[ -z "$tables" ]]; then
    echo "WARN: No tables found for database '$db_name' or could not connect."
    return
  fi

  echo "----------------------------------------"
  printf "%-40s | %s\n" "Table" "Row Count"
  echo "----------------------------------------"
  while read -r table; do
    # Get the row count for each table.
    count=$(mysql --user="$user" $sock_arg -sN -e "SELECT COUNT(*) FROM \`${db_name}\`.\`${table}\`;")
    printf "%-40s | %s\n" "$table" "$count"
  done <<< "$tables"
  echo "----------------------------------------"
}

validate_restore() {
  local dir=$1
  echo "→ Validating restore in $dir"
  local sock="${dir}/mysql.sock"
  # Use a non-standard port to avoid conflicts with a running instance
  local port=3307
  local pidfile="${dir}/mysql.pid"

  # Start a temporary mysqld instance from the restored data.
  # --skip-networking=1 is a security measure to prevent outside connections.
  mysqld --no-defaults --datadir="$dir" --socket="$sock" --port="$port" --pid-file="$pidfile" --skip-networking=1 &
  local pid=$!

  # Wait for the server to start by pinging it.
  local n=0
  local max_wait=30
  echo "  - Waiting for test server to start (PID: $pid)..."
  # MYSQL_PWD is already exported above so mysqladmin picks it up without --password.
  until mysqladmin --socket="$sock" --user="$MYSQL_USER" ping &>/dev/null; do
    ((n++)) || :
    if (( n >= max_wait )); then
      echo "ERROR: Test MySQL server failed to start after $n seconds." >&2
      kill "$pid" &>/dev/null || :
      return 1
    fi
    sleep 1
  done
  echo "  ✓ Test server started successfully."

  get_table_counts "$DATABASE_NAME" "$MYSQL_USER" "$sock"

  # Shut down the test server by PID — $MYSQL_USER lacks the MySQL SHUTDOWN privilege.
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

stop_mysql_server() {
  echo "  - Stopping MySQL service..."
  if sudo systemctl is-active --quiet mysql; then
    sudo systemctl stop mysql
    echo "✓ MySQL service stopped."
  else
    echo "✓ MySQL service is not running."
  fi
}

restore_primary_datadir() {
  local datadir
  # Get the datadir by asking the mysqld binary for its configuration.
  # This is more robust as it doesn't require a running server.
  datadir=$(mysqld --verbose --help | grep '^datadir' | awk '{print $2}')
  if [[ -z "$datadir" ]]; then
    echo "ERROR: Could not determine MySQL datadir from 'mysqld --verbose --help'." >&2
    exit 1
  fi

  local backup_size
  backup_size=$(du -sh "$PRIMARY_RESTORE" | awk '{print $1}')

  echo "→ Restoring to primary data directory: $datadir"
  echo "  - Source:      $PRIMARY_RESTORE"
  echo "  - Backup size: $backup_size"
  echo "WARNING: This is a destructive operation and requires sudo."

  # To avoid 'mv' errors, construct a backup path that is explicitly a sibling of the datadir.
  local parent_dir
  parent_dir=$(dirname "$datadir")
  local base_name
  base_name=$(basename "$datadir")
  local backup_path="${parent_dir}/${base_name}.bak.$(date +%s)"

  # Park the old datadir instead of deleting it: if the restored backup turns out
  # to be bad (only discovered when MySQL fails to start below), the pre-restore
  # data is still recoverable. mv on the same filesystem is an instant rename and
  # uses no extra disk space; the parked copy is removed manually after the
  # restore has been verified (command printed at the end of this function).
  echo "  - Parking old datadir at ${backup_path} (rollback: sudo mv ${backup_path} ${datadir})"
  sudo mv "$datadir" "$backup_path"

  echo "  - Moving data from $PRIMARY_RESTORE..."
  # Recreate the original datadir for the new data and copy the contents.
  sudo mkdir -p "$datadir"

  shopt -s dotglob nullglob
  sudo mv "$PRIMARY_RESTORE"/* "$datadir"/
  shopt -u dotglob nullglob

  echo "  - Setting permissions..."
  sudo chown -R mysql:mysql "$datadir"

  echo "  - Starting MySQL service..."
  sudo systemctl start mysql

  # Poll until MySQL accepts connections (up to 60s) instead of sleeping a fixed interval.
  local n=0
  local max_wait=60
  until mysqladmin --user="$MYSQL_USER" ping &>/dev/null; do
    ((n++)) || :
    if (( n >= max_wait )); then
      echo "ERROR: MySQL failed to start within ${max_wait}s after restore." >&2
      # The restore failed, but the pre-restore data was parked (not deleted),
      # so the operator can put the old datadir back and restart.
      echo "       Old datadir is intact at ${backup_path}." >&2
      echo "       Roll back with: sudo systemctl stop mysql && sudo rm -rf ${datadir} && sudo mv ${backup_path} ${datadir} && sudo systemctl start mysql" >&2
      exit 1
    fi
    sleep 1
  done
  echo "✓ Primary MySQL instance started successfully (waited ${n}s)."
  get_table_counts "$DATABASE_NAME" "$MYSQL_USER"

  # The old datadir is intentionally kept on disk until a human confirms the
  # restore is good — it may be the only remaining copy if the backup chain
  # is later found to be incomplete. Freeing the space is a deliberate step.
  echo "NOTE: old datadir kept at ${backup_path}"
  echo "      After verifying the restore, free the space with: sudo rm -rf ${backup_path}"
}

full_backup() {
    get_table_counts "$DATABASE_NAME" "$MYSQL_USER"
    echo "→ Performing full backup to S3: $FULL_NAME"
    # Stage the backup to a local file first to isolate issues.
    local backup_file="${TMPDIR}/${FULL_NAME}.xbstream"
    echo "  - Staging backup to local file: ${backup_file}"
    sudo mkdir -p "$LSNDIR"
    sudo xtrabackup --backup --compress --stream=xbstream --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" --host="$MYSQL_HOST" --port="$MYSQL_PORT" --target-dir="$TMPDIR" --extra-lsndir="$LSNDIR" > "${backup_file}"

    echo "  - Uploading staged backup to S3..."
    cat "${backup_file}" | xbcloud "${XB_ARGS[@]}" put "$FULL_NAME" 2>&1
}

incr_backup() {
    local last_lsn=""
    if sudo test -f "$LSNDIR/xtrabackup_checkpoints"; then
        last_lsn=$(sudo grep '^to_lsn' "$LSNDIR/xtrabackup_checkpoints" | awk '{print $3}')
    fi

    if [[ -n "$last_lsn" ]]; then
        echo "→ Performing incremental backup using LSN: $last_lsn"
        local incr_backup_file="${TMPDIR}/${INCR_NAME}.xbstream"
        echo "  - Staging incremental backup to local file: ${incr_backup_file}"
        sudo mkdir -p "$LSNDIR_INCR"
        sudo xtrabackup --backup --compress --stream=xbstream --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" --host="$MYSQL_HOST" --port="$MYSQL_PORT" --target-dir="$TMPDIR/inc" \
          --incremental-lsn="$last_lsn" --extra-lsndir="$LSNDIR_INCR" > "${incr_backup_file}"

        echo "  - Uploading staged incremental backup to S3..."
        cat "${incr_backup_file}" | xbcloud "${XB_ARGS[@]}" put "$INCR_NAME" 2>&1
    else
        echo "WARN: LSN not found or readable. Falling back to restoring full backup."
        local last_full_name
        last_full_name=$(get_latest_full)
        if [[ -z "$last_full_name" ]]; then
            echo "ERROR: Cannot perform incremental backup. No full backup found in S3." >&2
            return 1
        fi

        echo "→ Performing incremental backup to S3: $INCR_NAME (base: $last_full_name)"
        # The --incremental-basedir must point to the *data* of the last full backup.
        # For a standalone 'incr' command, we must first restore the base full backup.
        restore_full "$last_full_name" "$TMPDIR/base"

        local incr_backup_file="${TMPDIR}/${INCR_NAME}.xbstream"
        echo "  - Staging incremental backup to local file: ${incr_backup_file}"
        sudo xtrabackup --backup --compress --stream=xbstream --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" --host="$MYSQL_HOST" --port="$MYSQL_PORT" --target-dir="$TMPDIR/inc" \
          --incremental-basedir="$TMPDIR/base" > "${incr_backup_file}"

        echo "  - Uploading staged incremental backup to S3..."
        cat "${incr_backup_file}" | xbcloud "${XB_ARGS[@]}" put "$INCR_NAME" 2>&1
    fi
}

cleanup() {
  echo "→ Cleaning up temporary directory: $TMPDIR"
  rm -rf "$TMPDIR"
  sudo rm -rf /tmp/xb_*
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  full                  Perform a full backup.
  incr                  Perform an incremental backup. Requires a previous full backup.
  restore_test          Perform a full restore chain from latest backups and validate it.
  restore_primary       Perform a full restore chain from latest backups and promote it.
  restore_from_test <full_key> [incr_key]
                        Restore from a specific full and optional incremental backup and validate it.
                        Use "nil" for incr_key to restore from full backup only.
  restore_from_primary <full_key> [incr_key]
                        Restore from a specific full and optional incremental backup and promote it.
                        Use "nil" for incr_key to restore from full backup only.
EOF
  exit 1
}

# Exit quietly (status 0) when this host is not armed. Cron on every instance
# baked from the DB AMI fires this script; only the restored primary may write
# to the backup chain — a second writer would corrupt the restore lineage.
require_armed() {
  if [[ ! -f "$ARMED_MARKER" ]]; then
    echo "ℹ️ Backups not armed on this host (missing $ARMED_MARKER) — skipping."
    echo "   restore_primary arms automatically; manual arm: sudo touch $ARMED_MARKER"
    exit 0
  fi
}

main() {
  cleanup # Initialize: Clean up any previous temporary files
  mkdir -p "$TMPDIR"

  case "${1:-}" in
    full)
      require_armed
      full_backup
      ;;
    incr)
      require_armed
      incr_backup
      ;;
    restore_test)
      restore_latest_chain
      if validate_restore "$PRIMARY_RESTORE"; then
        echo "✅ Test restore succeeded."
      else
        echo "❌ Test restore failed."
        exit 1
      fi
      ;;
    restore_primary)
      stop_mysql_server
      restore_latest_chain
      restore_primary_datadir
      # A successful primary restore means this host now holds the real dataset:
      # arm the baked cron so the full/incr schedule resumes automatically.
      sudo touch "$ARMED_MARKER"
      echo "✓ Backups armed ($ARMED_MARKER created) — cron schedule is now live."
      echo "✅ Promote complete."
      ;;
    restore_from_test)
      if [[ $# -lt 2 || $# -gt 3 ]]; then
        echo "Usage: $0 restore_from_test <full_key> [incr_key]" >&2
        exit 1
      fi
      local full_key=$2
      local incr_key=${3:-}
      if [[ "$incr_key" == "nil" ]]; then
          incr_key=""
      fi
      prepare_restore_from_keys "$full_key" "$incr_key"
      if validate_restore "$PRIMARY_RESTORE"; then
        echo "✅ Test restore from specific backup succeeded."
      else
        echo "❌ Test restore from specific backup failed."
        exit 1
      fi
      ;;
    restore_from_primary)
      if [[ $# -lt 2 || $# -gt 3 ]]; then
        echo "Usage: $0 restore_from_primary <full_key> [incr_key]" >&2
        exit 1
      fi
      local full_key=$2
      local incr_key=${3:-}
      if [[ "$incr_key" == "nil" ]]; then
          incr_key=""
      fi
      stop_mysql_server
      prepare_restore_from_keys "$full_key" "$incr_key"
      restore_primary_datadir
      # Same as restore_primary: a promoted host is the real primary — arm it.
      sudo touch "$ARMED_MARKER"
      echo "✓ Backups armed ($ARMED_MARKER created) — cron schedule is now live."
      echo "✅ Promote from specific backup complete."
      ;;
    *)
      usage
      ;;
  esac

  cleanup
}

main "$@"

set +x
