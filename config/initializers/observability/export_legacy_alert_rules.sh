#!/usr/bin/env bash
# Dump the exact PromQL/thresholds/labels for the 9 alert rules that live
# outside grafana_provision.yml — the Disk, Memory, ResponseTimes and WebApp
# folders (see README.md "Alert reference" table). These were created by
# hand directly in the Grafana UI at some point and were never brought into
# the declarative rake-provisioned set.
#
# Run this, paste the summary table back, and grafana_provision.yml gets the
# 5 genuinely-new rules added faithfully instead of reconstructed from
# threshold descriptions alone. The 3 that duplicate an existing CapHive
# Alerts rule (Disk Usage >85%, High Memory usage <10% free, P99 Response
# Times >2.5s) are being dropped in favour of the tighter existing rule —
# this script still dumps them so that decision can be double-checked against
# the real query before the legacy copy is deleted from Grafana.
#
# Requires: GRAFANA_URL, GRAFANA_PASS env vars (same convention as
# `rake grafana:provision`). GRAFANA_USER defaults to admin. jq for formatting.
#
# Usage:
#   GRAFANA_PASS=xxx ./export_legacy_alert_rules.sh
#   GRAFANA_URL=https://graphana.caphive.us GRAFANA_PASS=xxx ./export_legacy_alert_rules.sh

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-https://graphana.caphive.com}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
: "${GRAFANA_PASS:?Set GRAFANA_PASS}"

if ! command -v jq >/dev/null; then
  echo "jq is required" >&2
  exit 1
fi

OUT_DIR="$(mktemp -d)"
FOLDERS=(Disk Memory ResponseTimes WebApp)

for folder in "${FOLDERS[@]}"; do
  echo "Fetching folder: $folder" >&2
  curl -sf -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    "${GRAFANA_URL}/api/ruler/grafana/api/v1/rules/${folder}" \
    -o "${OUT_DIR}/${folder}.json" \
    || echo "  (no rules found in folder '${folder}', or request failed)" >&2
done

echo
echo "=== Rule summary (title | expr | for | severity label | folder) ==="
for folder in "${FOLDERS[@]}"; do
  f="${OUT_DIR}/${folder}.json"
  [ -s "$f" ] || continue
  jq -r --arg folder "$folder" '
    .[][]
    | .rules[]
    | [
        $folder,
        .grafana_alert.title,
        (.for // "n/a"),
        (.labels.severity // "NONE"),
        (.grafana_alert.data[0].model.expr // .grafana_alert.data[-1].model.expr // "n/a")
      ]
    | @tsv
  ' "$f"
done | column -t -s $'\t' -N FOLDER,TITLE,FOR,SEVERITY,EXPR

echo
echo "Full JSON per folder saved under: ${OUT_DIR}"
echo "(paste that summary table back, or the raw JSON files if the expr column got truncated)"
