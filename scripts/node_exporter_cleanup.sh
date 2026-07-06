#!/bin/bash
# node_exporter_cleanup.sh
#
# Runs ON an app server (via SSH, see run_on_all_servers.sh). Goal: node_exporter must run
# NATIVELY (systemd), never inside Docker — a Dockerized node-exporter only ever sees its own
# container's mount namespace (Docker always injects just /etc/hostname, /etc/hosts,
# /etc/resolv.conf), so disk/inode metrics silently report nothing for that host. This:
#   1. Removes any Docker-based node-exporter container
#   2. Removes any crontab entry that would restart a Docker-based node-exporter
#   3. Installs the native systemd service if it's missing (using an existing working host
#      as the reference: /usr/local/bin/node_exporter + a dedicated system user)
#   4. Enables + starts the native service
#   5. Verifies port 9100 and real filesystem visibility

set -euo pipefail

NODE_EXPORTER_VERSION="1.8.2"
NODE_EXPORTER_USER="node_exporter"
ARCH="linux-amd64"

echo "=== $(hostname) ($(hostname -I | awk '{print $1}')) ==="

echo "--- Removing any Docker-based node-exporter ---"
if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "node-exporter"; then
  sudo docker rm -f node-exporter
  echo "  removed docker container 'node-exporter'"
else
  echo "  no docker container named 'node-exporter' found"
fi

echo "--- Removing any crontab entries that (re)start a docker node-exporter ---"
# `crontab -l` exits non-zero when the user has no crontab at all — that's a normal, expected
# state (not an error), so capture it with `|| true` rather than let it abort the whole script.
CRONTAB_CONTENT="$(crontab -l 2>/dev/null || true)"
if echo "${CRONTAB_CONTENT}" | grep -q "prom/node-exporter"; then
  echo "${CRONTAB_CONTENT}" | grep -v "prom/node-exporter" | crontab -
  echo "  removed matching crontab line(s)"
else
  echo "  no matching crontab entries"
fi

echo "--- Checking if node_exporter is already running natively ---"
if pgrep -x node_exporter >/dev/null 2>&1; then
  echo "  node_exporter process already running natively (pid(s): $(pgrep -x node_exporter | tr '\n' ' ')) — leaving binary/process untouched"
  echo "  (if this isn't managed by systemd, verify separately that it survives a reboot)"
  ALREADY_RUNNING=1
else
  echo "  no native node_exporter process found"
  ALREADY_RUNNING=0
fi

if [ "${ALREADY_RUNNING}" = 0 ]; then
  echo "--- Checking for native systemd service ---"
  if systemctl list-unit-files 2>/dev/null | grep -q "^node_exporter.service"; then
    echo "  node_exporter.service exists but isn't running — will (re)start it below"
  else
    echo "  node_exporter.service NOT found — installing native binary + unit"

    if ! id "${NODE_EXPORTER_USER}" &>/dev/null; then
      sudo useradd --no-create-home --shell /usr/sbin/nologin "${NODE_EXPORTER_USER}"
    fi

    TMPDIR=$(mktemp -d)
    pushd "${TMPDIR}" >/dev/null
    curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz" -o node_exporter.tar.gz
    tar xzf node_exporter.tar.gz
    sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter" /usr/local/bin/node_exporter
    sudo chown "${NODE_EXPORTER_USER}:${NODE_EXPORTER_USER}" /usr/local/bin/node_exporter
    popd >/dev/null
    rm -rf "${TMPDIR}"

    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
  fi

  echo "--- Ensuring native service is enabled + running ---"
  sudo systemctl enable --now node_exporter
else
  echo "--- Skipping install/enable — already running natively ---"
fi

echo "--- Who is actually on port 9100 now ---"
sudo ss -tlnp | grep 9100 || echo "  WARNING: nothing listening on 9100"

echo "--- Filesystem visibility check (should show mountpoint=\"/\", not just /etc/*) ---"
curl -s localhost:9100/metrics | grep node_filesystem_size_bytes || echo "  WARNING: no filesystem metrics returned"

echo "=== Done on $(hostname) ==="
