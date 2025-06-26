#!/usr/bin/env bash
set -euxo pipefail
IFS=$'\n\t'
# TODO
# 1. Restore from specific full & specific incremental, ensure the incremental is after full and allow for nil incr backups (i.e restore from full only)
# 2. Cleanup intermediate incr from S3 for > 30 days
# 3. Check if there is a way to do incr without downloading the full backup
# If not then no need to delete the full backup dir, during the day, reuse for every hourly incr

# To setup these ENVs run on the prod box
# RAILS_ENV=production rake xtrabackup:generate_backup_script 
# This generates a file with all vars setup

# This is the sequence to restore replica
# PROD Primary DB
# * ./db_backup.sh full
# * ./db_backup.sh incr


# PROD Replica DB
# 	./db_backup.sh restore_primary

# PROD App Server
# 	RAILS_ENV=production bundle exec rake db:reset_replication



export BUCKET="__BUCKET__"
export AWS_REGION="__AWS_REGION__"
export AWS_ACCESS_KEY_ID="__AWS_ACCESS_KEY_ID__"
export AWS_SECRET_ACCESS_KEY="__AWS_SECRET_ACCESS_KEY__"
export MYSQL_PASSWORD="__MYSQL_PASSWORD__"
export MYSQL_USER="__MYSQL_USER__"
export DATABASE_NAME="__DATABASE_NAME__"

# To setup these ENVs run on the prod box
# RAILS_ENV=production rake xtrabackup:generate_backup_script 
# This generates a file with all vars setup

export BUCKET="__BUCKET__"
export AWS_REGION="__AWS_REGION__"
export AWS_ACCESS_KEY_ID="__AWS_ACCESS_KEY_ID__"
export AWS_SECRET_ACCESS_KEY="__AWS_SECRET_ACCESS_KEY__"
export MYSQL_PASSWORD="__MYSQL_PASSWORD__"
export MYSQL_USER="__MYSQL_USER__"
export DATABASE_NAME="__DATABASE_NAME__"

# Required ENV
: "${AWS_ACCESS_KEY_ID:?}"
: "${AWS_SECRET_ACCESS_KEY:?}"
: "${AWS_REGION:?}"
: "${BUCKET:?}"
: "${DATABASE_NAME:?}"
: "${MYSQL_USER:?}"
: "${MYSQL_PASSWORD:?}"
: "${MYSQL_HOST:=localhost}"
: "${MYSQL_PORT:=3306}"

MYSQL_TMPDIR="${MYSQL_TMPDIR:-/tmp}"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION MYSQL_PWD="$MYSQL_PASSWORD"

XB_ARGS=(--storage=S3
         --s3-bucket="${BUCKET}"
         --s3-access-key="${AWS_ACCESS_KEY_ID}"
         --s3-secret-key="${AWS_SECRET_ACCESS_KEY}"
         --s3-region="${AWS_REGION}"
         --s3-endpoint="s3.${AWS_REGION}.amazonaws.com"
         --max-retries=5 --max-backoff=120000 --parallel=4)

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

get_latest_incr_since_full() {
  local full_key=$1
  get_all_incrs | while read -r incr_key; do
    if [[ "$incr_key" > "$full_key" ]]; then
      echo "$incr_key"
    fi
  done | tail -n 1
}

get_latest_full() {
  aws s3api list-objects-v2 --bucket "$BUCKET" --delimiter '/' \
    --query "CommonPrefixes[?ends_with(Prefix,'-full/')].Prefix | sort(@) | [-1]" \
    --output text | sed 's!/$!!'
}

restore_latest_chain() {
  local full_key
  full_key=$(get_latest_full)
  if [[ -z "$full_key" ]]; then
    echo "ERROR: No full backup found." >&2
    return 1
  fi
  echo "Found latest full backup: $full_key"

  local latest_incr
  latest_incr=$(get_latest_incr_since_full "$full_key")

  local incr_chain=()
  if [[ -n "$latest_incr" ]]; then
    echo "Found latest incremental backup to apply: $latest_incr"
    incr_chain+=("$latest_incr")
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
  rm -rf "$restore_to_primary" && cp -a "$STAGING_FULL" "$restore_to_primary"
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
  # Note: Assumes the root user has no password or it's set in a .my.cnf readable by the user.
  # For production, you'd need a more secure way to handle credentials.
  until mysqladmin --socket="$sock" --user=root ping &>/dev/null; do
    ((n++)) || :
    if (( n >= max_wait )); then
      echo "ERROR: Test MySQL server failed to start after $n seconds." >&2
      kill "$pid" &>/dev/null || :
      return 1
    fi
    sleep 1
  done
  echo "  ✓ Test server started successfully."

  # Get table counts from the restored data. Using 'root' as the user for the test instance.
  get_table_counts "$DATABASE_NAME" "root" "$sock"

  # Shutdown the test server and capture the exit code.
  mysqladmin --socket="$sock" --user=root shutdown
  wait "$pid"
  return $?
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

  # echo "  - Backing up old datadir to ${backup_path}..."
  sudo rm -rf "$datadir"

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

  echo "  - Waiting for service to be up..."
  sleep 10 # Simple wait, could be improved with a loop
  if ! mysqladmin --user="$MYSQL_USER" ping; then
      echo "ERROR: MySQL failed to start after restore." >&2
      exit 1
  fi
  echo "✓ Primary MySQL instance started successfully."
  get_table_counts "$DATABASE_NAME" "$MYSQL_USER"
}

full_backup() {
    get_table_counts "$DATABASE_NAME" "$MYSQL_USER"
    echo "→ Performing full backup to S3: $FULL_NAME"
    # Stage the backup to a local file first to isolate issues.
    local backup_file="${TMPDIR}/${FULL_NAME}.xbstream"
    echo "  - Staging backup to local file: ${backup_file}"
    sudo xtrabackup --backup --compress --stream=xbstream --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" --host="$MYSQL_HOST" --port="$MYSQL_PORT" --target-dir="$TMPDIR" > "${backup_file}"

    echo "  - Uploading staged backup to S3..."
    cat "${backup_file}" | xbcloud "${XB_ARGS[@]}" put "$FULL_NAME" 2>&1
}

incr_backup() {
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
}

cleanup() {
  echo "→ Cleaning up temporary directory: $TMPDIR"
  rm -rf "$TMPDIR"
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

main() {
  case "${1:-}" in
    full)
      full_backup
      ;;
    incr)
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
