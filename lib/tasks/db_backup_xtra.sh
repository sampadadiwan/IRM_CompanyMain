#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Required ENV
: "${AWS_ACCESS_KEY_ID:?}"
: "${AWS_SECRET_ACCESS_KEY:?}"
: "${AWS_REGION:?}"
: "${BUCKET:?}"
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
         --max-retries=5 --max-backoff=120000 --parallel=4)

TIMESTAMP="$(date +%F)"
FULL_NAME="${TIMESTAMP}-full"
INCR_NAME="${TIMESTAMP}-incr-$(date +%H%M)"
TMPDIR="${MYSQL_TMPDIR}/xb_$$"
LAST_FULL="${TMPDIR}/last_full"
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
    --query "CommonPrefixes[?contains(Prefix,'-incr-')].Prefix | sort(@)" \
    --output text | tr '\t' '\n' | sed 's!/$!!'
}

get_latest_full() {
  aws s3api list-objects-v2 --bucket "$BUCKET" --delimiter '/' \
    --query "CommonPrefixes[?ends_with(Prefix,'-full/')].Prefix | sort(@) | [-1]" \
    --output text | sed 's!/$!!'
}

restore_chain() {
  local full_key
  full_key=$(get_latest_full)
  if [[ -z "$full_key" ]]; then
    echo "ERROR: No full backup found." >&2
    return 1
  fi
  echo "Found latest full backup: $full_key"

  local all_incrs
  all_incrs=($(get_all_incrs))
  echo "Found ${#all_incrs[@]} total incremental backups."

  local incr_chain=()
  if (( ${#all_incrs[@]} > 0 )); then
    for incr_key in "${all_incrs[@]}"; do
      # This simple string comparison works because of the YYYY-MM-DD-incr-HHMM format
      if [[ "$incr_key" > "$full_key" ]]; then
        incr_chain+=("$incr_key")
      fi
    done
  fi

  echo "Using full backup: $full_key"
  if (( ${#incr_chain[@]} > 0 )); then
    echo "Applying ${#incr_chain[@]} incremental backups from the chain:"
    printf " - %s\n" "${incr_chain[@]}"
  else
    echo "No incremental backups found to apply for this full backup."
  fi

  # 1. Restore full backup
  restore_full "$full_key" "$LAST_FULL"

  # 2. Copy to staging.
  echo "→ Preparing staging directory by copying restored full backup"
  rm -rf "$STAGING_FULL"
  cp -a "$LAST_FULL" "$STAGING_FULL"

  # 3. Apply all incrementals in the chain
  for incr_key in "${incr_chain[@]}"; do
    apply_incremental "$incr_key" "$STAGING_FULL"
  done

  # 4. Final prepare on the staged backup
  final_prepare "$STAGING_FULL"

  # 5. Copy prepared backup to final restore directory
  echo "→ Copying prepared backup to final restore directory"
  local restore_to_primary="$PRIMARY_RESTORE"
  rm -rf "$restore_to_primary" && cp -a "$STAGING_FULL" "$restore_to_primary"
  echo "Restore chain complete. Data is in $restore_to_primary"
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

  # Shutdown the test server and capture the exit code.
  mysqladmin --socket="$sock" --user=root shutdown
  wait "$pid"
  return $?
}

restore_primary_datadir() {
  local datadir
  # Get the datadir from the running MySQL instance
  datadir=$(mysql --user="$MYSQL_USER" -e "SELECT @@datadir;" -sN)
  if [[ -z "$datadir" ]]; then
    echo "ERROR: Could not determine MySQL datadir." >&2
    exit 1
  fi

  echo "→ Restoring to primary data directory: $datadir"
  echo "  - Source: $PRIMARY_RESTORE"
  echo "WARNING: This is a destructive operation."

  # This command will vary based on the OS (e.g., service mysql stop)
  echo "  - Stopping MySQL service..."
  systemctl stop mysql

  echo "  - Backing up old datadir to ${datadir}.bak..."
  mv "$datadir" "${datadir}.bak.$(date +%s)"

  echo "  - Copying new data from $PRIMARY_RESTORE..."
  cp -a "$PRIMARY_RESTORE" "$datadir"

  echo "  - Setting permissions..."
  chown -R mysql:mysql "$datadir"

  echo "  - Starting MySQL service..."
  systemctl start mysql

  echo "  - Waiting for service to be up..."
  sleep 10 # Simple wait, could be improved with a loop
  if ! mysqladmin --user="$MYSQL_USER" ping; then
      echo "ERROR: MySQL failed to start after restore." >&2
      exit 1
  fi
}

full_backup() {
    echo "→ Performing full backup to S3: $FULL_NAME"
    # Stream the backup directly to xbcloud
    xtrabackup --backup --user="$MYSQL_USER" --host="$MYSQL_HOST" --port="$MYSQL_PORT" --target-dir="$TMPDIR" \
      | xbcloud "${XB_ARGS[@]}" put "$FULL_NAME"
    # Record the name of the last full backup for incrementals
    echo "$FULL_NAME" > "$LAST_FULL"
}

incr_backup() {
    local last_full_name
    if [[ ! -f "$LAST_FULL" ]]; then
        echo "ERROR: Cannot perform incremental backup. No record of last full backup found." >&2
        return 1
    fi
    last_full_name=$(<"$LAST_FULL")
    echo "→ Performing incremental backup to S3: $INCR_NAME (base: $last_full_name)"
    # The --incremental-basedir must point to the *data* of the last full backup.
    # The current logic assumes the last full backup was restored to TMPDIR, which might not be true.
    # For a standalone 'incr' command, we must first restore the base full backup.
    restore_full "$last_full_name" "$TMPDIR/base"

    xtrabackup --backup --user="$MYSQL_USER" --host="$MYSQL_HOST" --port="$MYSQL_PORT" --target-dir="$TMPDIR/inc" \
      --incremental-basedir="$TMPDIR/base" \
      | xbcloud "${XB_ARGS[@]}" put "$INCR_NAME"
}

cleanup() {
  echo "→ Cleaning up temporary directory: $TMPDIR"
  rm -rf "$TMPDIR"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  full            Perform a full backup.
  incr            Perform an incremental backup. Requires a previous full backup.
  restore_test    Perform a full restore chain and validate it in a temporary instance.
  restore_primary Perform a full restore chain and promote it to the primary data directory.
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
      restore_chain
      if validate_restore "$PRIMARY_RESTORE"; then
        echo "✅ Test restore succeeded."
      else
        echo "❌ Test restore failed."
        exit 1
      fi
      ;;
    restore_primary)
      restore_chain
      restore_primary_datadir
      echo "✅ Promote complete."
      ;;
    *)
      usage
      ;;
  esac

  cleanup
}

main "$@"
