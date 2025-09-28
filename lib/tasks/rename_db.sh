#!/usr/bin/env bash
# Fast, same-server schema "rename" using atomic RENAME TABLE (no data copy).
# Usage:
#   ./mysql_rename_db_fast.sh <old_db> <new_db> [mysql_user] [mysql_host] [mysql_port]
# Example:
#   ./mysql_rename_db_fast.sh caphive caphive_prod root 127.0.0.1 3306

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <old_db> <new_db> [mysql_user] [mysql_host] [mysql_port]" >&2
  exit 1
fi

OLD_DB="$1"
NEW_DB="$2"
MYSQL_USER="${3:-root}"
MYSQL_HOST="${4:-localhost}"
MYSQL_PORT="${5:-3306}"
CHUNK_SIZE="${CHUNK_SIZE:-200}"  # max table-pairs per RENAME statement

read -s -p "MySQL password for ${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}: " MYSQL_PWD
echo
export MYSQL_PWD

mysqlq() { mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -NBe "$1"; }
mysql_exec() { mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "$1"; }

# --- Preflight ---------------------------------------------------------------
echo "[*] Preflight checks…"
mysqlq "SELECT 1" >/dev/null

if ! mysqlq "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${OLD_DB}'" | grep -qx "${OLD_DB}"; then
  echo "ERROR: Old database '${OLD_DB}' does not exist." >&2
  exit 1
fi
if mysqlq "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${NEW_DB}'" | grep -qx "${NEW_DB}"; then
  echo "ERROR: New database '${NEW_DB}' already exists." >&2
  exit 1
fi

# --- Capture original globals to restore later --------------------------------
ORIG_READ_ONLY=$(mysqlq "SELECT @@GLOBAL.read_only;")
ORIG_EVENT_SCHED=$(mysqlq "SELECT @@GLOBAL.event_scheduler;")

restore_globals() {
  echo "[*] Restoring globals…"
  mysql_exec "SET GLOBAL read_only=${ORIG_READ_ONLY};" || true
  mysql_exec "SET GLOBAL event_scheduler='${ORIG_EVENT_SCHED}';" || true
}
trap restore_globals EXIT

# --- Create target DB ---------------------------------------------------------
echo "[*] Creating database \`${NEW_DB}\`…"
mysql_exec "CREATE DATABASE \`${NEW_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"

# --- Quiesce writes & pause events -------------------------------------------
echo "[*] Enabling read_only=ON (super user can still run DDL)…"
mysql_exec "SET GLOBAL read_only=ON;"
echo "[*] Temporarily disabling event_scheduler…"
mysql_exec "SET GLOBAL event_scheduler='OFF';"

# --- Extract object DDLs (views, routines, events, triggers) -----------------
WORKDIR="$(mktemp -d)"
DDL_FILE="${WORKDIR}/recreate_meta_in_${NEW_DB}.sql"
DROP_TRIG_FILE="${WORKDIR}/drop_triggers_${OLD_DB}.sql"
DISABLE_OLD_EVENTS_FILE="${WORKDIR}/disable_events_${OLD_DB}.sql"
touch "$DDL_FILE" "$DROP_TRIG_FILE" "$DISABLE_OLD_EVENTS_FILE"

echo "[*] Capturing metadata DDLs…"

# Views
while IFS=$'\t' read -r vname; do
  [[ -z "$vname" ]] && continue
  # 2nd column of SHOW CREATE VIEW is the CREATE statement
  CRE=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --skip-column-names -e "SHOW CREATE VIEW \`${OLD_DB}\`.\`${vname}\`" | awk -F'\t' 'NR==1{print $2}')
  [[ -z "$CRE" ]] || echo "${CRE};" >> "$DDL_FILE"
done < <(mysqlq "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA='${OLD_DB}';")

# Routines (procedures/functions)
while IFS=$'\t' read -r rname rtype; do
  [[ -z "$rname" ]] && continue
  CRE=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --skip-column-names -e "SHOW CREATE ${rtype} \`${OLD_DB}\`.\`${rname}\`" | awk -F'\t' 'NR==1{print $3}')
  [[ -z "$CRE" ]] || echo "${CRE};" >> "$DDL_FILE"
done < <(mysqlq "SELECT ROUTINE_NAME, ROUTINE_TYPE FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA='${OLD_DB}';")

# Events
while IFS=$'\t' read -r ename; do
  [[ -z "$ename" ]] && continue
  CRE=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --skip-column-names -e "SHOW CREATE EVENT \`${OLD_DB}\`.\`${ename}\`" | awk -F'\t' 'NR==1{print $3}')
  [[ -z "$CRE" ]] || echo "${CRE};" >> "$DDL_FILE"
  echo "ALTER EVENT \`${OLD_DB}\`.\`${ename}\` DISABLE;" >> "$DISABLE_OLD_EVENTS_FILE"
done < <(mysqlq "SELECT EVENT_NAME FROM INFORMATION_SCHEMA.EVENTS WHERE EVENT_SCHEMA='${OLD_DB}';")

# Triggers: capture CREATEs and prepare DROP list (must drop before cross-schema rename)
while IFS=$'\t' read -r tname; do
  [[ -z "$tname" ]] && continue
  CRE=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --skip-column-names -e "SHOW CREATE TRIGGER \`${OLD_DB}\`.\`${tname}\`" | awk -F'\t' 'NR==1{print $3}')
  [[ -z "$CRE" ]] || echo "${CRE};" >> "$DDL_FILE"
  echo "DROP TRIGGER \`${OLD_DB}\`.\`${tname}\`;" >> "$DROP_TRIG_FILE"
done < <(mysqlq "SELECT TRIGGER_NAME FROM INFORMATION_SCHEMA.TRIGGERS WHERE TRIGGER_SCHEMA='${OLD_DB}';")

# Rewrite ALL captured DDLs: neutralize DEFINER and move schema old_db -> new_db
sed -E -i \
  -e "s/DEFINER=\`[^\\`]*\`@\`[^\\`]*\`/DEFINER=CURRENT_USER/g" \
  -e "s/\\\`${OLD_DB}\\\`\\./\`${NEW_DB}\`./g" \
  "$DDL_FILE"

# --- Drop triggers in old_db --------------------------------------------------
if [[ -s "$DROP_TRIG_FILE" ]]; then
  echo "[*] Dropping triggers in \`${OLD_DB}\` (required for cross-schema rename)…"
  mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" < "$DROP_TRIG_FILE"
fi

# --- Build and run atomic RENAME TABLE in chunks ------------------------------
echo "[*] Renaming base tables from \`${OLD_DB}\` → \`${NEW_DB}\`…"
mapfile -t TABLES < <(mysqlq "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='${OLD_DB}' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;")

if [[ "${#TABLES[@]}" -eq 0 ]]; then
  echo "WARN: No base tables found in ${OLD_DB}."
else
  total=${#TABLES[@]}
  i=0
  while [[ $i -lt $total ]]; do
    chunk_end=$(( i + CHUNK_SIZE ))
    [[ $chunk_end -gt $total ]] && chunk_end=$total
    pairs=()
    for ((j=i; j<chunk_end; j++)); do
      t="${TABLES[j]}"
      pairs+=(" \`${OLD_DB}\`.\`${t}\` TO \`${NEW_DB}\`.\`${t}\` ")
    done
    SQL="RENAME TABLE $(IFS=,; echo "${pairs[*]}");"
    mysql_exec "$SQL"
    i=$chunk_end
  done
fi

# --- Recreate views/routines/events/triggers in new_db ------------------------
if [[ -s "$DDL_FILE" ]]; then
  echo "[*] Recreating views, routines, events, triggers in \`${NEW_DB}\`…"
  # Ensure we run inside new_db for any unqualified statements
  { echo "USE \`${NEW_DB}\`;"; cat "$DDL_FILE"; } | mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER"
fi

# --- Disable events in old_db so they don't restart accidentally --------------
if [[ -s "$DISABLE_OLD_EVENTS_FILE" ]]; then
  echo "[*] Disabling any remaining events in \`${OLD_DB}\`…"
  mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" < "$DISABLE_OLD_EVENTS_FILE"
fi

# --- Replicate GRANTs old_db.* -> new_db.* -----------------------------------
echo "[*] Replicating GRANTs from \`${OLD_DB}\`.* → \`${NEW_DB}\`.* …"
USERS=$(mysqlq "
  SELECT DISTINCT CONCAT(\"'\", user, \"'@'\", host, \"'\")
  FROM mysql.db WHERE db='${OLD_DB}'
  UNION
  SELECT DISTINCT CONCAT(\"'\", user, \"'@'\", host, \"'\")
  FROM mysql.tables_priv WHERE db='${OLD_DB}'
  UNION
  SELECT DISTINCT CONCAT(\"'\", user, \"'@'\", host, \"'\")
  FROM mysql.procs_priv WHERE db='${OLD_DB}';
")
if [[ -n "${USERS}" ]]; then
  while read -r U; do
    [[ -z "$U" ]] && continue
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --skip-column-names -e "SHOW GRANTS FOR ${U}" \
      | sed -E "s/ ON \`${OLD_DB}\`\\./ ON \`${NEW_DB}\`./g; s/ ON ${OLD_DB}\\./ ON ${NEW_DB}./g" \
      | awk 'NF' \
      | while read -r G; do
          if grep -q " ON \`${NEW_DB}\`\\." <<<"$G"; then
            mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "$G"
          fi
        done
  done <<< "$USERS"
else
  echo "    (No db-specific user privileges found.)"
fi

# --- Restore globals ----------------------------------------------------------
echo "[*] Restoring event_scheduler and read_only…"
restore_globals
trap - EXIT

echo
echo "[✓] Rename complete."
echo "    - Base tables moved to \`${NEW_DB}\`."
echo "    - Views / triggers / routines / events recreated in \`${NEW_DB}\`."
echo "    - Events in \`${OLD_DB}\` disabled."
echo
echo "Next steps:"
echo "  1) Point your apps to \`${NEW_DB}\` and verify."
echo "  2) When satisfied, DROP DATABASE \`${OLD_DB}\`; (this will remove old views/routines/etc.)."
echo "  3) Consider recreating DEFINERs explicitly if you need non-CURRENT_USER owners."
