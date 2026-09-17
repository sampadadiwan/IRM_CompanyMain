#!/usr/bin/env bash
# Deletes the 9 legacy alert rules (Disk/Memory/ResponseTimes/WebApp folders) now
# that all 5 worth keeping have been migrated into grafana_provision.yml and the
# other 4 were confirmed as duplicates of a rule already in that file — see the
# "Deleted" list in README.md's Alert reference section for exactly why each one
# was dropped rather than migrated.
#
# RUN ORDER MATTERS: run this only AFTER `rake grafana:provision:alert_rules` has
# been applied successfully. Doing it first would leave a real gap — e.g. no
# Node Alive coverage at all — between the delete and the next provision run.
#
# The Grafana ruler API deletes a whole rule group at a time (no per-rule delete
# in this Grafana version — see README.md "Known quirks"), which is fine here
# since every rule in each of these 4 groups is being retired one way or another.
#
# Requires: GRAFANA_URL, GRAFANA_PASS env vars (same convention as
# `rake grafana:provision`). GRAFANA_USER defaults to admin.
#
# Usage:
#   GRAFANA_PASS=xxx ./delete_legacy_alert_folders.sh          # dry run, lists what would be deleted
#   GRAFANA_PASS=xxx ./delete_legacy_alert_folders.sh --yes    # actually deletes

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-https://graphana.caphive.com}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
: "${GRAFANA_PASS:?Set GRAFANA_PASS}"
CONFIRM="${1:-}"

# folder:group pairs, from the live Grafana Alerting UI as of 2026-08-22
# NOTE: do not name this array GROUPS — that's a bash builtin (the invoking
# user's Unix group IDs), and assigning it gets silently shadowed/ignored.
LEGACY_GROUPS=(
  "Disk:Disk"
  "Memory:1Min"
  "ResponseTimes:1Min"
  "WebApp:1Min"
)

echo "Target Grafana: ${GRAFANA_URL}"
echo "Groups to delete:"
for pair in "${LEGACY_GROUPS[@]}"; do
  echo "  - ${pair%%:*} / ${pair##*:}"
done
echo

if [ "$CONFIRM" != "--yes" ]; then
  echo "Dry run only — nothing deleted. Re-run with --yes to actually delete these groups."
  echo "(Have you already run 'rake grafana:provision:alert_rules' with the migrated rules? If not, do that first.)"
  exit 0
fi

for pair in "${LEGACY_GROUPS[@]}"; do
  folder="${pair%%:*}"
  group="${pair##*:}"
  echo "Deleting ${folder}/${group}..."
  curl -sf -u "${GRAFANA_USER}:${GRAFANA_PASS}" -X DELETE \
    "${GRAFANA_URL}/api/ruler/grafana/api/v1/rules/${folder}/${group}" \
    && echo "  done" \
    || echo "  failed (already deleted, or check credentials/folder name)"
done
