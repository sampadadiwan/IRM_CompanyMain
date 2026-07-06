#!/bin/bash
# node_exporter_fleet.sh
#
# Runs node_exporter_cleanup.sh across app and/or DB servers, in one or both regions, over SSH.
#
# Usage:
#   ./node_exporter_fleet.sh [app|db|all] [in|us|both]
#
# Defaults to "all" roles in "both" regions if no args given.
#
# SSH keys are hardcoded (override via IN_KEY/US_KEY env vars if these ever change):
#   US:  ~/.ssh/caphive2.us.pem for every US server (app + DB)
#   IN:  ~/.ssh/caphive2.pem for IN app servers; IN's DB servers take a DIFFERENT key
#        (~/.ssh/caphive.pem) that only lives on the IN bastion itself, not locally —
#        see IN_BASTION_DB_KEY below.
#
# DB servers only have private IPs, unreachable directly from outside the VPC. Instead of
# requiring you to SSH into an app server first, DB connections are tunneled through that
# region's first app server as an SSH jump host automatically — run this from your laptop
# and it Just Works.
#
# Examples:
#   ./node_exporter_fleet.sh                  # everything, both regions
#   ./node_exporter_fleet.sh db               # DB servers only, both regions (via bastion)
#   ./node_exporter_fleet.sh db in            # DB servers, IN region only (via bastion)

set -euo pipefail

ROLE="${1:-all}"    # app | db | all
REGION="${2:-both}" # in | us | both

SSH_USER="${SSH_USER:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hardcoded local key paths — override via env var if these ever change.
IN_KEY="${IN_KEY:-$HOME/.ssh/caphive2.pem}"
US_KEY="${US_KEY:-$HOME/.ssh/caphive2.us.pem}"

# App servers use public IPs (reachable directly, e.g. matches config/deploy/production_*.rb).
# DB servers use private IPs (only reachable from inside the VPC), so DB traffic is tunneled
# through the region's first app server as an SSH jump host (-J) — no need to manually log into
# the app server first.
IN_APP_SERVERS=(15.206.165.118 35.154.185.236)
IN_DB_SERVERS=(10.0.3.182 10.0.4.78)
US_APP_SERVERS=(54.147.171.162 35.153.176.117)
US_DB_SERVERS=(10.0.3.214 10.0.4.28)

IN_BASTION="${IN_APP_SERVERS[0]}"
US_BASTION="${US_APP_SERVERS[0]}"

# IN's DB servers accept a DIFFERENT key than the app servers — one that only lives on the
# bastion itself (not locally), so it can't be used as a local -i/ProxyCommand identity. Instead,
# for IN/db we nest a second `ssh` command that runs ON the bastion, using ITS OWN copy of this
# key path to reach the DB server. US's DB servers accept the same key as the US app servers, so
# US keeps using the simpler local ProxyCommand tunnel (IN_BASTION_DB_KEY left blank for US).
IN_BASTION_DB_KEY="~/.ssh/caphive.pem"

run_host() {
  local region="$1" role="$2" host="$3" key="$4" bastion="$5" bastion_db_key="$6"

  echo "===================================================="
  echo "=== [${region}/${role}] ${host}$( [ -n "${bastion}" ] && echo " (via ${bastion})" ) ==="
  echo "===================================================="

  local ok=0
  if [ -n "${bastion}" ] && [ -n "${bastion_db_key}" ]; then
    # Double-hop: authenticate to the bastion locally, then run a second ssh FROM the bastion
    # using its own copy of bastion_db_key to reach the DB host. The cleanup script is piped in
    # as stdin and passes through both non-interactive hops untouched.
    local bastion_opts=(-o ConnectTimeout=10)
    [ -n "${key}" ] && [ -f "${key}" ] && bastion_opts+=(-i "${key}")
    if ssh "${bastion_opts[@]}" "${SSH_USER}@${bastion}" \
        "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -i ${bastion_db_key} ${SSH_USER}@${host} 'bash -s'" \
        < "${SCRIPT_DIR}/node_exporter_cleanup.sh"; then
      ok=1
    fi
  else
    local ssh_opts=(-o ConnectTimeout=10)
    [ -n "${key}" ] && [ -f "${key}" ] && ssh_opts+=(-i "${key}")
    if [ -n "${bastion}" ]; then
      # -J only accepts a bare [user@]host — it can't carry a per-hop -i flag. Use ProxyCommand
      # instead, which lets the jump hop use the same identity file as the final destination.
      local proxy_cmd="ssh -o ConnectTimeout=10 -W %h:%p"
      [ -n "${key}" ] && [ -f "${key}" ] && proxy_cmd="${proxy_cmd} -i ${key}"
      proxy_cmd="${proxy_cmd} ${SSH_USER}@${bastion}"
      ssh_opts+=(-o "ProxyCommand=${proxy_cmd}")
    fi
    if ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" 'bash -s' < "${SCRIPT_DIR}/node_exporter_cleanup.sh"; then
      ok=1
    fi
  fi

  if [ "${ok}" = 1 ]; then
    echo "  OK: ${host}"
  else
    echo "  !! FAILED on ${host} — check output above"
  fi
  echo
}

run_region() {
  local region="$1" role="$2" key="$3" bastion="$4" bastion_db_key="$5"
  shift 5
  local hosts=("$@")
  for host in "${hosts[@]}"; do
    run_host "${region}" "${role}" "${host}" "${key}" "${bastion}" "${bastion_db_key}"
  done
}

[[ "${REGION}" == "in" || "${REGION}" == "both" ]] && do_in=1 || do_in=0
[[ "${REGION}" == "us" || "${REGION}" == "both" ]] && do_us=1 || do_us=0
[[ "${ROLE}" == "app" || "${ROLE}" == "all" ]] && do_app=1 || do_app=0
[[ "${ROLE}" == "db"  || "${ROLE}" == "all" ]] && do_db=1  || do_db=0

# App servers: connect directly (public IP). DB servers: tunnel via that region's bastion app server.
if [ "${do_in}" = 1 ] && [ "${do_app}" = 1 ]; then run_region "IN" "app" "${IN_KEY:-}" ""             ""                    "${IN_APP_SERVERS[@]}"; fi
if [ "${do_in}" = 1 ] && [ "${do_db}"  = 1 ]; then run_region "IN" "db"  "${IN_KEY:-}" "${IN_BASTION}" "${IN_BASTION_DB_KEY}" "${IN_DB_SERVERS[@]}";  fi
if [ "${do_us}" = 1 ] && [ "${do_app}" = 1 ]; then run_region "US" "app" "${US_KEY:-}" ""             ""                    "${US_APP_SERVERS[@]}"; fi
if [ "${do_us}" = 1 ] && [ "${do_db}"  = 1 ]; then run_region "US" "db"  "${US_KEY:-}" "${US_BASTION}" ""                    "${US_DB_SERVERS[@]}";  fi

echo "Done. Every host's 'Filesystem visibility check' section above should show"
echo "mountpoint=\"/\" — if any host still only shows /etc/*, something is still wrong there."
