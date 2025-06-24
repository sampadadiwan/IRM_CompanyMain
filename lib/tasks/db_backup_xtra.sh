#!/usr/bin/env bash
#
# backup_db.sh – daily full / hourly incremental backups
#                (no-Docker edition)
#
# Requires:
#   • percona-xtrabackup-80   (xbstream & xtrabackup on PATH)
#   • percona-server-80 (or upstream mysql-server 8.0/8.4)
#   • awscli v1 or v2
#   • rsync, lsof, jq (optional), util-linux (for flock), gzip
#
# ------------------------------------------------------------------
set -euo pipefail

MODE=${1:-""}                                      # full | inc | restore
TS=$(date +%F_%H-%M-%S)                            # 2025-06-24_14-00-00

# ── configurable bits ──────────────────────────────────────────────
MYSQL_DATADIR=/var/lib/mysql                       # running instance
BACKUP_ROOT=/srv/mysql-backups
XB_BIN=/usr/bin/xtrabackup                         # point to host binary
MYSQLD_BIN=/usr/sbin/mysqld
MYSQL_BIN=/usr/bin/mysql
DB_USER=root
DB_PASS='Root1234$'
DB_HOST=127.0.0.1
DB_PORT=3306
S3_BUCKET="${S3_BUCKET:-}"                         # export beforehand
TMPDIR=${TMPDIR:-/tmp}
PARALLEL=$(nproc --ignore=1 || echo 1)
# ───────────────────────────────────────────────────────────────────

################################################################################
# sanity‐checks – bail early if something obvious is missing
################################################################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌  Missing $1 – abort"; exit 9; }; }
need awk; need rsync; need sed; need "$XB_BIN"; need aws
[[ -x "$MYSQLD_BIN" ]] || { echo "❌  $MYSQLD_BIN not executable"; exit 9; }

[[ -z "$MODE" || ( "$MODE" != full && "$MODE" != inc && "$MODE" != restore ) ]] \
  && { echo "Usage: $0 {full|inc|restore}"; exit 1; }

[[ -z "$S3_BUCKET" && "$MODE" != restore ]] \
  && { echo "Please export S3_BUCKET=your-bucket"; exit 2; }

sudo chown -R "$USER":"$USER" "$BACKUP_ROOT"

#############################################
# Return newest full_*/inc_* directory
#############################################
latest_dir() {
  local newest
  newest=$(sudo ls -1dt "${BACKUP_ROOT}"/{inc,full}_* 2>/dev/null | head -1 || true)
  echo "$newest"
}

cleanup_local() {
  echo "[INFO] Cleaning up old backups (keeping newest chain)…"
  local keep; keep=$(latest_dir)
  sudo find "${BACKUP_ROOT}" -maxdepth 1 -type d -name '*_*' \
       ! -path "${keep}" -exec rm -rf {} +
}

run_xb() {         # wrapper around host xtrabackup
  sudo "$XB_BIN" "$@"
}

prepare_merge() {  # $1 base  $2 [inc]
  run_xb --prepare --apply-log-only --target-dir="$1" --parallel="$PARALLEL"
  [[ -n "${2:-}" ]] && \
    run_xb --prepare --target-dir="$1" --incremental-dir="$2" --parallel="$PARALLEL"
}

###############################################################################
# crash_test – verify a prepared backup boots cleanly
# Args: $1  path to prepared (–--prepare) backup directory
# -----------------------------------------------------------------------------
# • runs as root the whole time → no rsync “permission denied”
# • skips #innodb_redo (safe – redo logs are regenerated on start-up)
# • picks a random free port so it never collides with production MySQL
# • waits ≤60 s for “ready for connections”, then shuts the test server down
###############################################################################
###############################################################################
# crash_test – verify a prepared backup boots cleanly
# Args: $1  prepared-backup directory (already --prepare’d)
###############################################################################
crash_test() {
  local PREP_DIR="$1"
  local TMP_DATA
  TMP_DATA=$(mktemp -d "${TMPDIR:-/tmp}/xbtest-XXXX") || return 8

  echo "[INFO] Crash-test mysqld – copying prepared backup (root → $TMP_DATA)…"
  # Copy everything **except** bulky redo *files*,
  # but still create the directory they live in.
  sudo rsync -a --delete \
       --exclude='#innodb_redo/ib_redo*' \
       "$PREP_DIR"/ "$TMP_DATA"/

  # Ensure the mandatory folder exists even if rsync excluded it
  sudo mkdir -p "$TMP_DATA/#innodb_redo"

  # Hand out ownership so mysqld (run with sudo) can access files
  sudo chown -R mysql:mysql "$TMP_DATA"

  # Launch throw-away server on a random free port
  local TEST_PORT SOCKET PID_FILE ERR_LOG
  TEST_PORT=$(shuf -i 3400-3999 -n1)
  SOCKET="$TMP_DATA/mysql.sock"
  PID_FILE="$TMP_DATA/mysqld.pid"
  ERR_LOG="$TMP_DATA/error.log"

  echo "[INFO] Launching temporary mysqld on port $TEST_PORT…"
  sudo mysqld \
       --datadir="$TMP_DATA" \
       --socket="$SOCKET" \
       --port="$TEST_PORT" \
       --skip-grant-tables \
       --pid-file="$PID_FILE" \
       --log-error="$ERR_LOG" \
       --daemonize

  # wait ≤60 s for “ready for connections”
  for _ in {1..60}; do
      sudo grep -q "ready for connections" "$ERR_LOG" && break
      sleep 1
  done

  if ! sudo grep -q "ready for connections" "$ERR_LOG"; then
      echo "[ERROR] Crash-test mysqld did not start – see $ERR_LOG"
      sudo cat "$ERR_LOG" | sed 's/^/    /'
      sudo kill "$(cat "$PID_FILE")" 2>/dev/null || true
      sudo rm -rf "$TMP_DATA"
      return 8
  fi

  if [[ -z "${KEEP_TEST:-}" ]]; then
    echo "[INFO] Crash-test passed – shutting down test server."
    sudo mysqladmin --socket="$SOCKET" shutdown
    sudo rm -rf "$TMP_DATA"
  else
      echo "[INFO] Test server left running for manual checks."
  fi
}


###############################################################
# Upload a backup directory to S3 (unchanged from your script)
###############################################################
upload_s3() {
  local SRC_DIR="$1" KEY DEST TMP_LOG
  KEY=$(basename "$SRC_DIR"); DEST="s3://${S3_BUCKET}/${KEY}/"
  TMP_LOG="/tmp/${KEY}_upload_$(date +%s).log"
  local AWS_VER MAJOR HR_FLAG=""; AWS_VER="$(aws --version 2>&1 | awk '{print $1}')"
  MAJOR="$(echo "$AWS_VER" | cut -d'/' -f2 | cut -d'.' -f1)"; [[ $MAJOR == 2 ]] && HR_FLAG="--human-readable"
  printf "\e[36m[%s] [INFO] Uploading %s ➜ %s\e[0m\n" "$(date '+%F %T')" "$SRC_DIR" "$DEST"
  sudo -E aws s3 cp "$SRC_DIR" "$DEST" --recursive $HR_FLAG --only-show-errors | tee -a "$TMP_LOG"
  local AWS_RC=${PIPESTATUS[0]}
  sudo cp "$TMP_LOG" "${SRC_DIR}/upload_${KEY}.log"
  (( AWS_RC == 0 )) \
     && printf "\e[32m[%s] [SUCCESS] S3 upload finished\e[0m\n" "$(date '+%F %T')" \
     || { printf "\e[31m[%s] [ERROR] S3 upload FAILED – see %s\e[0m\n" "$(date '+%F %T')" "$TMP_LOG"; exit 9; }
}

###############################################################################
# Restore newest full + incrementals from S3 and start mysqld on a free port
###############################################################################
restore_latest() {
  : "${AWS_DEFAULT_REGION:=ap-south-1}"
  printf '\e[36m[%s] Listing s3://%s\e[0m\n' "$(date '+%F %T')" "$S3_BUCKET"
  mapfile -t KEYS < <(aws s3 ls "s3://$S3_BUCKET/" | awk '{print $NF}' | sed 's:/$::')
  [[ ${#KEYS[@]} -eq 0 ]] && { echo "Bucket empty"; exit 5; }
  FULL_KEY=$(printf '%s\n' "${KEYS[@]}" | grep '^full_' | sort | tail -1)
  [[ -z $FULL_KEY ]] && { echo "No full_ backup on S3"; exit 6; }
  INC_KEYS=$(printf '%s\n' "${KEYS[@]}" | grep '^inc_' | awk -v ts="${FULL_KEY#full_}" '$0 > ("inc_" ts)' | sort)
  echo "Full backup     : $FULL_KEY"
  [[ -n $INC_KEYS ]] && echo "Incrementals    : $INC_KEYS" || echo "Incrementals    : (none)"
  FULL_DIR="${BACKUP_ROOT}/${FULL_KEY}"; sudo mkdir -p "$FULL_DIR"
  echo "[INFO] Downloading full …"; sudo -E aws s3 cp "s3://$S3_BUCKET/$FULL_KEY" "$FULL_DIR" --recursive
  for k in $INC_KEYS; do echo "[INFO] Downloading $k …"; sudo -E aws s3 cp "s3://$S3_BUCKET/$k" "${BACKUP_ROOT}/${k}" --recursive; done
  sudo chmod -R u+rw "$FULL_DIR"; sudo mkdir -p "$FULL_DIR/#innodb_redo" && sudo chmod 700 "$FULL_DIR/#innodb_redo"
  echo "[INFO] Preparing base (apply-log-only)"; run_xb --prepare --apply-log-only --target-dir="$FULL_DIR" --parallel="$PARALLEL"
  for k in $INC_KEYS; do
      echo "[INFO] Merging $k"; run_xb --prepare --apply-log-only --target-dir="$FULL_DIR" --incremental-dir="${BACKUP_ROOT}/${k}" --parallel="$PARALLEL"
  done
  echo "[INFO] Final prepare"; run_xb --prepare --target-dir="$FULL_DIR" --parallel="$PARALLEL"
  echo "[INFO] Crash-test restored data"; crash_test "$FULL_DIR"
  local RESTORE_PORT; RESTORE_PORT=$(shuf -i 3400-3999 -n1)
  echo "[INFO] Launching mysqld on port $RESTORE_PORT (socket $FULL_DIR/mysql.sock)"
  ( cd "$FULL_DIR" && sudo "$MYSQLD_BIN" \
        --datadir="$FULL_DIR" --socket="$FULL_DIR/mysql.sock" \
        --port="$RESTORE_PORT" --skip-grant-tables --pid-file="$FULL_DIR/mysqld.pid" & )
  printf '\e[32m[%s] ✅  Restore complete – server listening on port %s (socket %s/mysql.sock)\e[0m\n' \
         "$(date '+%F %T')" "$RESTORE_PORT" "$FULL_DIR"
}

###############################################################################
# MAIN
###############################################################################
case "$MODE" in
  full)
    TARGET="${BACKUP_ROOT}/full_${TS}"
    run_xb --backup \
           --datadir="${MYSQL_DATADIR}" \
           --target-dir="$TARGET" \
           --host="${DB_HOST}" --port="${DB_PORT}" \
           --user="${DB_USER}" --password="${DB_PASS}" \
           --parallel="$PARALLEL"
    sudo chmod -R a+rX "$TARGET"
    upload_s3 "$TARGET"
    ;;
  inc)
    BASE=$(latest_dir) || { echo "No base backup; run full first"; exit 4; }
    TARGET="${BACKUP_ROOT}/inc_${TS}"
    run_xb --backup \
           --datadir="${MYSQL_DATADIR}" \
           --target-dir="$TARGET" \
           --incremental-basedir="$BASE" \
           --host="${DB_HOST}" --port="${DB_PORT}" \
           --user="${DB_USER}" --password="${DB_PASS}" \
           --parallel="$PARALLEL"
    upload_s3 "$TARGET"
    cleanup_local
    ;;
  restore)  restore_latest ;;
esac
