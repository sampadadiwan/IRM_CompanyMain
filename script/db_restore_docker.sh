#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Description: Restore MySQL XtraBackup from S3 into a Docker container.
# This script handles version mismatches by allowing you to specify the MySQL version.
# Configuration (Inherited from environment or defaults)
: "${BUCKET:=docs.caphive.us.production.us-east-1-backup-xtra}"
: "${AWS_REGION:=us-east-1}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${MYSQL_PASSWORD:=Root1234$}"
: "${MYSQL_USER:=root}"
: "${DATABASE_NAME:=IRM_production}"
: "${MYSQL_VERSION:=8.4}" # Default to 8.4 as per the backup version found
: "${CONTAINER_NAME:=mysql-restored}"
: "${PORT:=33066}"



# Internal paths
MYSQL_TMPDIR="${MYSQL_TMPDIR:-/tmp}"
TMPDIR="${MYSQL_TMPDIR}/xb_docker_$$"
STAGING_DIR="${TMPDIR}/staging"
RESTORE_DIR="${TMPDIR}/restore"

mkdir -p "$STAGING_DIR" "$RESTORE_DIR"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION MYSQL_PWD="$MYSQL_PASSWORD"

XB_ARGS=(--storage=S3
         --s3-bucket="${BUCKET}"
         --s3-access-key="${AWS_ACCESS_KEY_ID}"
         --s3-secret-key="${AWS_SECRET_ACCESS_KEY}"
         --s3-region="${AWS_REGION}"
         --s3-endpoint="s3.${AWS_REGION}.amazonaws.com"
         --max-retries=5 --max-backoff=120000 --parallel=4)

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

cleanup() {
  echo "→ Cleaning up temporary directory: $TMPDIR"
  rm -rf "$STAGING_DIR"
}

get_latest_full() {
  aws s3api list-objects-v2 \
    --bucket "$BUCKET" \
    --delimiter '/' \
    --query "CommonPrefixes[?ends_with(Prefix, '-full/')].Prefix" \
    --output text | tr '\t' '\n' | sed 's!/$!!' | sort -V | tail -n1
}

get_all_incrs() {
  aws s3api list-objects-v2 --bucket "$BUCKET" --delimiter '/' \
    --query "CommonPrefixes[?ends_with(Prefix,'-incr/')].Prefix | sort(@)" \
    --output text | tr '\t' '\n' | sed 's!/$!!'
}

get_all_incrs_since_full() {
  local full_key=$1
  get_all_incrs | while read -r incr_key; do
    if [[ "$incr_key" > "$full_key" ]]; then
      echo "$incr_key"
    fi
  done
}

restore_full() {
  local key=$1 dir=$2
  echo "→ Downloading full backup '$key'..."
  retry 3 xbcloud "${XB_ARGS[@]}" get "$key" | xbstream -x -C "$dir"
  echo "→ Decompressing..."
  xtrabackup --decompress --target-dir="$dir" --remove-original
  echo "→ Preparing (apply-log-only)..."
  xtrabackup --prepare --apply-log-only --target-dir="$dir"
}

apply_incremental() {
  local key=$1 base_dir=$2
  local incr_tmp_dir="${TMPDIR}/incr_stage"
  rm -rf "$incr_tmp_dir" && mkdir -p "$incr_tmp_dir"

  echo "→ Downloading incremental '$key'..."
  retry 3 xbcloud "${XB_ARGS[@]}" get "$key" | xbstream -x -C "$incr_tmp_dir"
  echo "→ Decompressing incremental..."
  xtrabackup --decompress --target-dir="$incr_tmp_dir" --remove-original
  echo "→ Applying incremental to base..."
  xtrabackup --prepare --apply-log-only --target-dir="$base_dir" --incremental-dir="$incr_tmp_dir"
  rm -rf "$incr_tmp_dir"
}

final_prepare() {
  local dir=$1
  echo "→ Final prepare..."
  xtrabackup --prepare --target-dir="$dir"
}

run_docker_mysql() {
  local data_dir=$1
  echo "→ Starting MySQL $MYSQL_VERSION in Docker container '$CONTAINER_NAME'..."

  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

  docker run -d \
    --name "$CONTAINER_NAME" \
    -e MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD" \
    -v "$(realpath "$data_dir")":/var/lib/mysql \
    -p "${PORT}":3306 \
    "mysql:${MYSQL_VERSION}"

  echo "→ Waiting for MySQL to start..."
  local max_wait=60
  local n=0
  until docker exec "$CONTAINER_NAME" mysqladmin -u root -p"$MYSQL_PASSWORD" ping &>/dev/null; do
    ((n++)) || :
    if (( n >= max_wait )); then
      echo "ERROR: MySQL container failed to start. Logs:"
      docker logs "$CONTAINER_NAME"
      exit 1
    fi
    sleep 2
  done

  echo "✅ MySQL is up and running on port ${PORT}."
  echo "   Connect using: mysql -h 127.0.0.1 -P ${PORT} -u root -p'$MYSQL_PASSWORD'"

  echo "→ Table counts for $DATABASE_NAME:"
  docker exec "$CONTAINER_NAME" mysql -u root -p"$MYSQL_PASSWORD" -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = '${DATABASE_NAME}';"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [full_key] [incr_key]

Commands:
  restore_primary       Perform a full restore chain from latest backups and promote it to Docker.
  restore_from_primary <full_key> [incr_key]
                        Restore from a specific full and optional incremental backup and promote it to Docker.
                        Use "nil" for incr_key to restore from full backup only.

Environment variables:
  MYSQL_VERSION   Default: 8.4 (Set to 8.0 for older backups)
  CONTAINER_NAME  Default: mysql-restored
  MYSQL_PASSWORD  Default: Root1234$
  PORT            Default: 33066
EOF
  exit 1
}

main() {
  local cmd=${1:-}
  local full_key=${2:-}
  local incr_key=${3:-}

  case "$cmd" in
    restore_primary)
      full_key=$(get_latest_full)
      if [[ -z "$full_key" ]]; then
        echo "ERROR: No full backup found." >&2
        exit 1
      fi
      echo "Using latest full backup: $full_key"
      restore_full "$full_key" "$RESTORE_DIR"

      local latest_incr
      latest_incr=$(get_all_incrs_since_full "$full_key" | tail -n1)
      if [[ -n "$latest_incr" ]]; then
        echo "Using latest incremental backup: $latest_incr"
        apply_incremental "$latest_incr" "$RESTORE_DIR"
      fi
      ;;
    restore_from_primary)
      if [[ -z "$full_key" ]]; then
        echo "Usage: $0 restore_from_primary <full_key> [incr_key]" >&2
        exit 1
      fi
      echo "Using full backup: $full_key"
      restore_full "$full_key" "$RESTORE_DIR"

      if [[ -n "$incr_key" && "$incr_key" != "nil" ]]; then
        echo "Using incremental backup: $incr_key"
        apply_incremental "$incr_key" "$RESTORE_DIR"
      fi
      ;;
    *)
      usage
      ;;
  esac

  final_prepare "$RESTORE_DIR"
  echo "→ Adjusting permissions for Docker..."
  sudo chown -R 999:999 "$RESTORE_DIR"
  run_docker_mysql "$RESTORE_DIR"
  cleanup
}

main "$@"
