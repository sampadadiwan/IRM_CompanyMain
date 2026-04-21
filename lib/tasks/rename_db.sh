#!/usr/bin/env bash
# ==============================================================================
# MySQL Fast Same-Server Schema Clone / Rename
# ==============================================================================
#
# Purpose
# -------
# Fast "rename" / clone of a MySQL schema on the same server using atomic
# RENAME TABLE, followed by recreation of metadata objects and repair of any
# cross-schema foreign keys that still reference the old schema.
#
# Why this version is safer
# -------------------------
# - Keeps logic modular and readable
# - Uses a single MySQL command wrapper
# - Restores globals reliably on exit
# - Rebuilds foreign keys using full metadata, including:
#   - multi-column foreign keys
#   - correct column order
#   - ON UPDATE / ON DELETE rules
# - Avoids the lossy one-column FK recreation bug
#
# Usage
# -----
#   ./mysql_rename_db_fast.sh <old_db> <new_db> [mysql_user] [mysql_host] [mysql_port]
#
# Parameters:
#   <old_db>    : Name of the existing database to be renamed.
#   <new_db>    : Name of the new database to be created.
#   [mysql_user]: (Optional) MySQL username. Defaults to 'root'.
#   [mysql_host]: (Optional) MySQL host. Defaults to 'localhost'.
#   [mysql_port]: (Optional) MySQL port. Defaults to '3306'.
#
# Example:
#   ./mysql_rename_db_fast.sh caphive caphive_prod root 127.0.0.1 3306
#
# Mechanism:
# 1. Performs preflight checks (source exists, target doesn't).
# 2. Captures original global settings (read_only, event_scheduler).
# 3. Creates the target database with utf8mb4 character set.
# 4. Sets global read_only=ON and disables event_scheduler to quiesce writes.
# 5. Extracts DDLs for views, routines, events, and triggers.
# 6. Neutralizes DEFINER and updates schema references in captured DDLs.
# 7. Drops triggers in the old database (required for cross-schema rename).
# 8. Renames base tables in chunks using RENAME TABLE ... TO ...
# 9. Recreates views, routines, events, and triggers in the new database.
# 10. Replicates grants from the old database to the new one.
# 11. Restores global settings.
# ==============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_MYSQL_USER="root"
readonly DEFAULT_MYSQL_HOST="localhost"
readonly DEFAULT_MYSQL_PORT="3306"
readonly DEFAULT_CHUNK_SIZE="200"

OLD_DB="${1:-}"
NEW_DB="${2:-}"
MYSQL_USER="${3:-$DEFAULT_MYSQL_USER}"
MYSQL_HOST="${4:-$DEFAULT_MYSQL_HOST}"
MYSQL_PORT="${5:-$DEFAULT_MYSQL_PORT}"
CHUNK_SIZE="${CHUNK_SIZE:-$DEFAULT_CHUNK_SIZE}"

if [[ -z "${OLD_DB}" || -z "${NEW_DB}" ]]; then
  echo "Usage: ${SCRIPT_NAME} <old_db> <new_db> [mysql_user] [mysql_host] [mysql_port]" >&2
  exit 1
fi

if [[ "${OLD_DB}" == "${NEW_DB}" ]]; then
  echo "ERROR: old_db and new_db must be different." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

log() {
  printf '[*] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# ------------------------------------------------------------------------------
# Credentials / mysql helpers
# ------------------------------------------------------------------------------

read -r -s -p "MySQL password for ${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}: " MYSQL_PWD
echo
export MYSQL_PWD

MYSQL_BASE_CMD=(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER")
MYSQL_BATCH_CMD=(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -NBe)

mysql_query() {
  local sql="$1"
  "${MYSQL_BATCH_CMD[@]}" "$sql"
}

mysql_exec() {
  local sql="$1"
  "${MYSQL_BASE_CMD[@]}" -e "$sql"
}

mysql_exec_file() {
  local file="$1"
  "${MYSQL_BASE_CMD[@]}" < "$file"
}

mysql_exec_stdin() {
  "${MYSQL_BASE_CMD[@]}"
}

# ------------------------------------------------------------------------------
# Globals restored on exit
# ------------------------------------------------------------------------------

ORIG_READ_ONLY=""
ORIG_EVENT_SCHED=""
ORIG_FK_CHECKS=""
WORKDIR=""
DDL_FILE=""
DROP_TRIG_FILE=""
DISABLE_OLD_EVENTS_FILE=""
FK_REBUILD_FILE=""
CLEANUP_DONE="false"

cleanup() {
  local exit_code=$?

  if [[ "${CLEANUP_DONE}" != "true" ]]; then
    CLEANUP_DONE="true"

    if [[ -n "${ORIG_FK_CHECKS}" ]]; then
      log "Restoring GLOBAL foreign_key_checks=${ORIG_FK_CHECKS}..."
      mysql_exec "SET GLOBAL foreign_key_checks=${ORIG_FK_CHECKS};" || true
    fi

    if [[ -n "${ORIG_EVENT_SCHED}" ]]; then
      log "Restoring GLOBAL event_scheduler='${ORIG_EVENT_SCHED}'..."
      mysql_exec "SET GLOBAL event_scheduler='${ORIG_EVENT_SCHED}';" || true
    fi

    if [[ -n "${ORIG_READ_ONLY}" ]]; then
      log "Restoring GLOBAL read_only=${ORIG_READ_ONLY}..."
      mysql_exec "SET GLOBAL read_only=${ORIG_READ_ONLY};" || true
    fi

    if [[ -n "${WORKDIR}" && -d "${WORKDIR}" ]]; then
      rm -rf "${WORKDIR}" || true
    fi
  fi

  exit "${exit_code}"
}

trap cleanup EXIT

# ------------------------------------------------------------------------------
# Validation helpers
# ------------------------------------------------------------------------------

require_mysql_connectivity() {
  log "Checking MySQL connectivity..."
  mysql_query "SELECT 1;" >/dev/null
}

schema_exists() {
  local schema_name="$1"
  mysql_query "SELECT SCHEMA_NAME
               FROM INFORMATION_SCHEMA.SCHEMATA
               WHERE SCHEMA_NAME='${schema_name}';" | grep -qx "${schema_name}"
}

capture_original_globals() {
  log "Capturing original global settings..."
  ORIG_READ_ONLY="$(mysql_query "SELECT @@GLOBAL.read_only;")"
  ORIG_EVENT_SCHED="$(mysql_query "SELECT @@GLOBAL.event_scheduler;")"
  ORIG_FK_CHECKS="$(mysql_query "SELECT @@GLOBAL.foreign_key_checks;")"
}

preflight_checks() {
  require_mysql_connectivity

  schema_exists "${OLD_DB}" || die "Old database '${OLD_DB}' does not exist."

  if schema_exists "${NEW_DB}"; then
    die "New database '${NEW_DB}' already exists."
  fi

  capture_original_globals
}

# ------------------------------------------------------------------------------
# Environment preparation
# ------------------------------------------------------------------------------

prepare_workdir() {
  WORKDIR="$(mktemp -d)"
  DDL_FILE="${WORKDIR}/recreate_meta_in_${NEW_DB}.sql"
  DROP_TRIG_FILE="${WORKDIR}/drop_triggers_${OLD_DB}.sql"
  DISABLE_OLD_EVENTS_FILE="${WORKDIR}/disable_events_${OLD_DB}.sql"
  FK_REBUILD_FILE="${WORKDIR}/rebuild_foreign_keys_${NEW_DB}.sql"

  touch "${DDL_FILE}" "${DROP_TRIG_FILE}" "${DISABLE_OLD_EVENTS_FILE}" "${FK_REBUILD_FILE}"
}

create_target_database() {
  log "Creating database \`${NEW_DB}\`..."
  mysql_exec "CREATE DATABASE \`${NEW_DB}\`
              CHARACTER SET utf8mb4
              COLLATE utf8mb4_0900_ai_ci;"
}

quiesce_server_activity() {
  log "Setting GLOBAL read_only=ON..."
  mysql_exec "SET GLOBAL read_only=ON;"

  log "Setting GLOBAL event_scheduler='OFF'..."
  mysql_exec "SET GLOBAL event_scheduler='OFF';"
}

# ------------------------------------------------------------------------------
# Metadata capture
# ------------------------------------------------------------------------------

capture_views() {
  log "Capturing VIEW DDL..."

  while IFS=$'\t' read -r view_name; do
    [[ -z "${view_name}" ]] && continue

    local create_sql=""
    create_sql="$("${MYSQL_BASE_CMD[@]}" --skip-column-names \
      -e "SHOW CREATE VIEW \`${OLD_DB}\`.\`${view_name}\`" \
      | awk -F'\t' 'NR==1 {print $2}')"

    [[ -n "${create_sql}" ]] && printf '%s;\n' "${create_sql}" >> "${DDL_FILE}"
  done < <(
    mysql_query "
      SELECT TABLE_NAME
      FROM INFORMATION_SCHEMA.VIEWS
      WHERE TABLE_SCHEMA='${OLD_DB}'
      ORDER BY TABLE_NAME;
    "
  )
}

capture_routines() {
  log "Capturing PROCEDURE/FUNCTION DDL..."

  while IFS=$'\t' read -r routine_name routine_type; do
    [[ -z "${routine_name}" ]] && continue

    local create_sql=""
    create_sql="$("${MYSQL_BASE_CMD[@]}" --skip-column-names \
      -e "SHOW CREATE ${routine_type} \`${OLD_DB}\`.\`${routine_name}\`" \
      | awk -F'\t' 'NR==1 {print $3}')"

    [[ -n "${create_sql}" ]] && printf '%s;\n' "${create_sql}" >> "${DDL_FILE}"
  done < <(
    mysql_query "
      SELECT ROUTINE_NAME, ROUTINE_TYPE
      FROM INFORMATION_SCHEMA.ROUTINES
      WHERE ROUTINE_SCHEMA='${OLD_DB}'
      ORDER BY ROUTINE_TYPE, ROUTINE_NAME;
    "
  )
}

capture_events() {
  log "Capturing EVENT DDL..."

  while IFS=$'\t' read -r event_name; do
    [[ -z "${event_name}" ]] && continue

    local create_sql=""
    create_sql="$("${MYSQL_BASE_CMD[@]}" --skip-column-names \
      -e "SHOW CREATE EVENT \`${OLD_DB}\`.\`${event_name}\`" \
      | awk -F'\t' 'NR==1 {print $3}')"

    [[ -n "${create_sql}" ]] && printf '%s;\n' "${create_sql}" >> "${DDL_FILE}"
    printf 'ALTER EVENT `%s`.`%s` DISABLE;\n' "${OLD_DB}" "${event_name}" >> "${DISABLE_OLD_EVENTS_FILE}"
  done < <(
    mysql_query "
      SELECT EVENT_NAME
      FROM INFORMATION_SCHEMA.EVENTS
      WHERE EVENT_SCHEMA='${OLD_DB}'
      ORDER BY EVENT_NAME;
    "
  )
}

capture_triggers() {
  log "Capturing TRIGGER DDL..."

  while IFS=$'\t' read -r trigger_name; do
    [[ -z "${trigger_name}" ]] && continue

    local create_sql=""
    create_sql="$("${MYSQL_BASE_CMD[@]}" --skip-column-names \
      -e "SHOW CREATE TRIGGER \`${OLD_DB}\`.\`${trigger_name}\`" \
      | awk -F'\t' 'NR==1 {print $3}')"

    [[ -n "${create_sql}" ]] && printf '%s;\n' "${create_sql}" >> "${DDL_FILE}"
    printf 'DROP TRIGGER `%s`.`%s`;\n' "${OLD_DB}" "${trigger_name}" >> "${DROP_TRIG_FILE}"
  done < <(
    mysql_query "
      SELECT TRIGGER_NAME
      FROM INFORMATION_SCHEMA.TRIGGERS
      WHERE TRIGGER_SCHEMA='${OLD_DB}'
      ORDER BY TRIGGER_NAME;
    "
  )
}

rewrite_captured_ddl() {
  log "Rewriting captured DDL for new schema and neutralized DEFINER..."

  sed -E -i \
    -e 's/DEFINER=`[^`]*`@`[^`]*`/DEFINER=CURRENT_USER/g' \
    -e "s/\`${OLD_DB}\`\./\`${NEW_DB}\`\./g" \
    "${DDL_FILE}"
}

capture_metadata_ddls() {
  capture_views
  capture_routines
  capture_events
  capture_triggers
  rewrite_captured_ddl
}

# ------------------------------------------------------------------------------
# Trigger drop prior to cross-schema table rename
# ------------------------------------------------------------------------------

drop_old_triggers() {
  if [[ -s "${DROP_TRIG_FILE}" ]]; then
    log "Dropping triggers in \`${OLD_DB}\` before cross-schema RENAME TABLE..."
    mysql_exec_file "${DROP_TRIG_FILE}"
  fi
}

# ------------------------------------------------------------------------------
# Table rename
# ------------------------------------------------------------------------------

rename_base_tables() {
  log "Collecting base tables from \`${OLD_DB}\`..."

  mapfile -t tables < <(
    mysql_query "
      SELECT TABLE_NAME
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA='${OLD_DB}'
        AND TABLE_TYPE='BASE TABLE'
      ORDER BY TABLE_NAME;
    "
  )

  if [[ "${#tables[@]}" -eq 0 ]]; then
    warn "No base tables found in ${OLD_DB}."
    return
  fi

  log "Temporarily disabling GLOBAL foreign_key_checks..."
  mysql_exec "SET GLOBAL foreign_key_checks=0;"

  log "Renaming ${#tables[@]} base tables from \`${OLD_DB}\` to \`${NEW_DB}\` in chunks of ${CHUNK_SIZE}..."

  local total="${#tables[@]}"
  local start=0

  while [[ "${start}" -lt "${total}" ]]; do
    local end=$(( start + CHUNK_SIZE ))
    (( end > total )) && end="${total}"

    local pairs=()
    local idx
    for (( idx=start; idx<end; idx++ )); do
      local table_name="${tables[idx]}"
      pairs+=("\`${OLD_DB}\`.\`${table_name}\` TO \`${NEW_DB}\`.\`${table_name}\`")
    done

    local sql="RENAME TABLE $(IFS=,; echo "${pairs[*]}");"
    mysql_exec "${sql}"

    start="${end}"
  done
}

# ------------------------------------------------------------------------------
# Foreign key repair
# ------------------------------------------------------------------------------

generate_fk_rebuild_sql() {
  log "Generating foreign key rebuild SQL for constraints still pointing to \`${OLD_DB}\`..."

  local fk_rows=""
  fk_rows="$(mysql_query "
    SELECT
      kcu.TABLE_NAME,
      kcu.CONSTRAINT_NAME,
      GROUP_CONCAT(CONCAT('\`', kcu.COLUMN_NAME, '\`') ORDER BY kcu.ORDINAL_POSITION SEPARATOR ', ') AS fk_columns,
      kcu.REFERENCED_TABLE_NAME,
      GROUP_CONCAT(CONCAT('\`', kcu.REFERENCED_COLUMN_NAME, '\`') ORDER BY kcu.POSITION_IN_UNIQUE_CONSTRAINT SEPARATOR ', ') AS ref_columns,
      rc.UPDATE_RULE,
      rc.DELETE_RULE
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
    JOIN INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc
      ON rc.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA
     AND rc.TABLE_NAME = kcu.TABLE_NAME
     AND rc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
    WHERE kcu.TABLE_SCHEMA = '${NEW_DB}'
      AND kcu.REFERENCED_TABLE_SCHEMA = '${OLD_DB}'
    GROUP BY
      kcu.TABLE_NAME,
      kcu.CONSTRAINT_NAME,
      kcu.REFERENCED_TABLE_NAME,
      rc.UPDATE_RULE,
      rc.DELETE_RULE
    ORDER BY
      kcu.TABLE_NAME,
      kcu.CONSTRAINT_NAME;
  ")"

  if [[ -z "${fk_rows}" ]]; then
    log "No foreign keys in \`${NEW_DB}\` still reference \`${OLD_DB}\`."
    return
  fi

  while IFS=$'\t' read -r table_name constraint_name fk_columns ref_table ref_columns update_rule delete_rule; do
    [[ -z "${table_name}" || -z "${constraint_name}" ]] && continue

    printf 'ALTER TABLE `%s`.`%s` DROP FOREIGN KEY `%s`;\n' \
      "${NEW_DB}" "${table_name}" "${constraint_name}" >> "${FK_REBUILD_FILE}"

    printf 'ALTER TABLE `%s`.`%s` ADD CONSTRAINT `%s` FOREIGN KEY (%s) REFERENCES `%s`.`%s` (%s)' \
      "${NEW_DB}" "${table_name}" "${constraint_name}" "${fk_columns}" "${NEW_DB}" "${ref_table}" "${ref_columns}" \
      >> "${FK_REBUILD_FILE}"

    if [[ -n "${delete_rule}" && "${delete_rule}" != "RESTRICT" ]]; then
      printf ' ON DELETE %s' "${delete_rule}" >> "${FK_REBUILD_FILE}"
    fi

    if [[ -n "${update_rule}" && "${update_rule}" != "RESTRICT" ]]; then
      printf ' ON UPDATE %s' "${update_rule}" >> "${FK_REBUILD_FILE}"
    fi

    printf ';\n' >> "${FK_REBUILD_FILE}"
  done <<< "${fk_rows}"
}

rebuild_foreign_keys() {
  generate_fk_rebuild_sql

  if [[ -s "${FK_REBUILD_FILE}" ]]; then
    log "Rebuilding foreign keys to point at \`${NEW_DB}\`..."
    mysql_exec_file "${FK_REBUILD_FILE}"
  fi

  log "Restoring GLOBAL foreign_key_checks=1..."
  mysql_exec "SET GLOBAL foreign_key_checks=1;"
}

# ------------------------------------------------------------------------------
# Metadata recreation and old event disable
# ------------------------------------------------------------------------------

recreate_metadata_in_new_schema() {
  if [[ -s "${DDL_FILE}" ]]; then
    log "Recreating views, routines, events, and triggers in \`${NEW_DB}\`..."
    {
      printf 'USE `%s`;\n' "${NEW_DB}"
      cat "${DDL_FILE}"
    } | mysql_exec_stdin
  fi
}

disable_old_events() {
  if [[ -s "${DISABLE_OLD_EVENTS_FILE}" ]]; then
    log "Disabling events remaining in \`${OLD_DB}\`..."
    mysql_exec_file "${DISABLE_OLD_EVENTS_FILE}"
  fi
}

# ------------------------------------------------------------------------------
# Grant replication
# ------------------------------------------------------------------------------

replicate_grants() {
  log "Replicating grants from \`${OLD_DB}\`.* to \`${NEW_DB}\`.* ..."

  local users=""
  users="$(mysql_query "
    SELECT DISTINCT CONCAT(\"'\", user, \"'@'\", host, \"'\")
    FROM mysql.db
    WHERE db='${OLD_DB}'

    UNION

    SELECT DISTINCT CONCAT(\"'\", user, \"'@'\", host, \"'\")
    FROM mysql.tables_priv
    WHERE db='${OLD_DB}'

    UNION

    SELECT DISTINCT CONCAT(\"'\", user, \"'@'\", host, \"'\")
    FROM mysql.procs_priv
    WHERE db='${OLD_DB}';
  ")"

  if [[ -z "${users}" ]]; then
    log "(No db-specific user privileges found.)"
    return
  fi

  while read -r user_spec; do
    [[ -z "${user_spec}" ]] && continue

    "${MYSQL_BASE_CMD[@]}" --skip-column-names -e "SHOW GRANTS FOR ${user_spec}" \
      | sed -E \
          -e "s/ ON \`${OLD_DB}\`\./ ON \`${NEW_DB}\`\./g" \
          -e "s/ ON ${OLD_DB}\./ ON ${NEW_DB}\./g" \
      | awk 'NF' \
      | while read -r grant_sql; do
          if grep -q " ON \`${NEW_DB}\`\." <<< "${grant_sql}"; then
            "${MYSQL_BASE_CMD[@]}" -e "${grant_sql}"
          fi
        done
  done <<< "${users}"
}

# ------------------------------------------------------------------------------
# Post-checks
# ------------------------------------------------------------------------------

verify_no_cross_schema_foreign_keys() {
  log "Checking for foreign keys in \`${NEW_DB}\` that still reference other schemas..."

  local leftovers=""
  leftovers="$(mysql_query "
    SELECT CONCAT(TABLE_NAME, '.', CONSTRAINT_NAME, ' -> ', REFERENCED_TABLE_SCHEMA, '.', REFERENCED_TABLE_NAME)
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA='${NEW_DB}'
      AND REFERENCED_TABLE_SCHEMA IS NOT NULL
      AND REFERENCED_TABLE_SCHEMA <> '${NEW_DB}'
    ORDER BY TABLE_NAME, CONSTRAINT_NAME;
  ")"

  if [[ -n "${leftovers}" ]]; then
    warn "Some foreign keys still reference other schemas:"
    printf '%s\n' "${leftovers}" >&2
    warn "Review these before using the cloned schema."
  else
    log "All foreign keys in \`${NEW_DB}\` now reference \`${NEW_DB}\` (or are non-FK columns)."
  fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
  preflight_checks
  prepare_workdir
  create_target_database
  quiesce_server_activity
  capture_metadata_ddls
  drop_old_triggers
  rename_base_tables
  rebuild_foreign_keys
  recreate_metadata_in_new_schema
  disable_old_events
  replicate_grants
  verify_no_cross_schema_foreign_keys

  echo
  echo "[✓] Rename / clone complete."
  echo "    - Base tables moved from \`${OLD_DB}\` to \`${NEW_DB}\`."
  echo "    - Views / triggers / routines / events recreated in \`${NEW_DB}\`."
  echo "    - Foreign keys repaired to reference \`${NEW_DB}\`."
  echo "    - Events in \`${OLD_DB}\` disabled."
  echo
  echo "Next steps:"
  echo "  1) Point the application to \`${NEW_DB}\` and verify core workflows."
  echo "  2) Run: SHOW CREATE TABLE on critical tables to spot-check constraints."
  echo "  3) When satisfied, DROP DATABASE \`${OLD_DB}\`."
  echo "  4) If needed, recreate DEFINERs explicitly instead of CURRENT_USER."

  CLEANUP_DONE="false"
}

main "$@"