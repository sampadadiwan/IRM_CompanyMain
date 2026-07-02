#!/usr/bin/env bash
# DB server observability setup — run on EACH DB server (primary and replica)
#
# Installs:
#   1. node_exporter   (port 9100) — OS metrics: CPU, memory, disk, network
#   2. mysqld_exporter (port 9104) — MySQL metrics: connections, QPS, replication lag
#
# Usage:
#   ssh ubuntu@<DB_SERVER_IP> -i ~/.ssh/caphive2.pem
#   export MONITOR_PASS="<choose-a-password>"
#   export MYSQL_ROOT_PASS="$(bundle exec rails runner 'puts Rails.application.credentials[:DB_PASS]')"
#   sudo -E bash < <(cat config/initializers/observability/mysqld_exporter/setup.sh)
#
# After running, replace DB_REPLICA_IP in prometheus.prod.yml with this server's
# internal IP (shown at the end of this script), then reload Prometheus:
#   docker kill -s HUP prometheus

set -euo pipefail

# Must run as root — the script installs system binaries and systemd services
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run this script as root:"
  echo "  sudo -E bash ./setup.sh"
  exit 1
fi

NODE_EXPORTER_VERSION="1.8.2"
MYSQL_EXPORTER_VERSION="0.16.0"
MONITOR_USER="exporter"
MONITOR_PASS="${MONITOR_PASS:?Set MONITOR_PASS env var before running}"
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:?Set MYSQL_ROOT_PASS env var before running}"
INSTALL_DIR="/usr/local/bin"
CNF_FILE="/etc/.mysqld_exporter.cnf"
MYSQLD_SERVICE_FILE="/etc/systemd/system/mysqld_exporter.service"
NODE_SERVICE_FILE="/etc/systemd/system/node_exporter.service"
ARCH="amd64"

# ── 1. node_exporter ────────────────────────────────────────────────────────

echo "=== Installing node_exporter v${NODE_EXPORTER_VERSION} ==="

# Check if anything is already listening on :9100 (Docker or systemd)
if ss -tlnp | grep -q ':9100'; then
  echo "  port 9100 already in use (Docker or systemd node_exporter), skipping install"
else
  NODE_TARBALL="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
  NODE_TARBALL_PATH="/tmp/${NODE_TARBALL}"
  NODE_EXTRACT_DIR="/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}"
  # Clean up any stale files from a previous failed run
  rm -rf "${NODE_TARBALL_PATH}" "${NODE_EXTRACT_DIR}"
  curl -L -o "${NODE_TARBALL_PATH}" "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${NODE_TARBALL}"
  tar xzf "${NODE_TARBALL_PATH}" -C /tmp
  cp "${NODE_EXTRACT_DIR}/node_exporter" "${INSTALL_DIR}/"
  chmod +x "${INSTALL_DIR}/node_exporter"
  rm -rf "${NODE_TARBALL_PATH}" "${NODE_EXTRACT_DIR}"

  # Dedicated system user — no shell, no home dir, can't log in
  if id node_exporter &>/dev/null; then
    echo "  user node_exporter already exists"
  else
    useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
    echo "  user node_exporter created"
  fi

  cat > "${NODE_SERVICE_FILE}" <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable node_exporter
  systemctl start node_exporter
  sleep 5
  if systemctl is-active --quiet node_exporter; then
    echo "  node_exporter service is active on :9100"
  else
    echo "  ERROR: node_exporter service failed to start"
    journalctl -u node_exporter -n 20 --no-pager
    exit 1
  fi
fi

# ── 2. mysqld_exporter ───────────────────────────────────────────────────────

echo "=== Installing mysqld_exporter v${MYSQL_EXPORTER_VERSION} ==="

# Stop the service first — can't overwrite a running binary ("Text file busy")
systemctl stop mysqld_exporter 2>/dev/null || true

MYSQL_TARBALL="mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
MYSQL_TARBALL_PATH="/tmp/${MYSQL_TARBALL}"
MYSQL_EXTRACT_DIR="/tmp/mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-${ARCH}"
rm -rf "${MYSQL_TARBALL_PATH}" "${MYSQL_EXTRACT_DIR}"
curl -L -o "${MYSQL_TARBALL_PATH}" "https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQL_EXPORTER_VERSION}/${MYSQL_TARBALL}"
tar xzf "${MYSQL_TARBALL_PATH}" -C /tmp
cp "${MYSQL_EXTRACT_DIR}/mysqld_exporter" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/mysqld_exporter"
rm -rf "${MYSQL_TARBALL_PATH}" "${MYSQL_EXTRACT_DIR}"
echo "  binary installed"

# Create MySQL monitoring user — MYSQL_PWD avoids the password appearing in ps output
echo "=== Creating MySQL monitoring user '${MONITOR_USER}'@'localhost' ==="
# Try mysql_native_password first (MySQL 5.7 / 8.0); fall back to default auth
# plugin (caching_sha2_password) for MySQL 8.4+ where mysql_native_password was removed.
if MYSQL_PWD="${MYSQL_ROOT_PASS}" mysql -u root -e "SELECT 1" &>/dev/null; then
  if MYSQL_PWD="${MYSQL_ROOT_PASS}" mysql -u root -e "SHOW PLUGINS" | grep -i 'mysql_native_password' | grep -qi 'ACTIVE'; then
    MYSQL_PWD="${MYSQL_ROOT_PASS}" mysql -u root <<SQL
CREATE USER IF NOT EXISTS '${MONITOR_USER}'@'localhost'
  IDENTIFIED WITH mysql_native_password BY '${MONITOR_PASS}'
  WITH MAX_USER_CONNECTIONS 3;
ALTER USER '${MONITOR_USER}'@'localhost'
  IDENTIFIED WITH mysql_native_password BY '${MONITOR_PASS}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO '${MONITOR_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo "  user created with mysql_native_password"
  else
    # MySQL 8.4+ — use default auth plugin (caching_sha2_password)
    MYSQL_PWD="${MYSQL_ROOT_PASS}" mysql -u root <<SQL
CREATE USER IF NOT EXISTS '${MONITOR_USER}'@'localhost'
  IDENTIFIED BY '${MONITOR_PASS}'
  WITH MAX_USER_CONNECTIONS 3;
ALTER USER '${MONITOR_USER}'@'localhost'
  IDENTIFIED BY '${MONITOR_PASS}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO '${MONITOR_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo "  user created with default auth plugin (MySQL 8.4+)"
  fi
else
  echo "  WARNING: could not connect to MySQL as root — skipping user creation"
  echo "  Create the user manually and re-run, or ensure MYSQL_ROOT_PASS is correct"
fi
echo "  monitoring user setup complete (read-only, localhost only, max 3 connections)"

# Dedicated system user for the exporter process
useradd --system --no-create-home --shell /sbin/nologin mysqld_exporter 2>/dev/null || true

# Write credentials file — owned by the exporter user, not readable by others
cat > "${CNF_FILE}" <<EOF
[client]
user=${MONITOR_USER}
password=${MONITOR_PASS}
EOF
chmod 600 "${CNF_FILE}"
chown mysqld_exporter:mysqld_exporter "${CNF_FILE}"
echo "  credentials written to ${CNF_FILE} (mode 600, owner mysqld_exporter)"

# Build ExecStart into a variable so the heredoc below has no shell variables to expand
EXEC_START="${INSTALL_DIR}/mysqld_exporter --config.my-cnf=${CNF_FILE} --collect.global_status --collect.global_variables --collect.slave_status --collect.info_schema.innodb_metrics --collect.info_schema.processlist --collect.info_schema.tables --collect.perf_schema.file_events --web.listen-address=:9104"

cat > "${MYSQLD_SERVICE_FILE}" <<UNIT
[Unit]
Description=Prometheus MySQL Exporter
After=network.target mysql.service

[Service]
User=mysqld_exporter
ExecStart=${EXEC_START}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable mysqld_exporter
systemctl restart mysqld_exporter
echo "  service started (running as mysqld_exporter user)"

# ── 3. Verify ────────────────────────────────────────────────────────────────

sleep 2
if curl -s http://localhost:9104/metrics | grep -q 'mysql_up 1'; then
  INTERNAL_IP="$(hostname -I | awk '{print $1}')"
  echo ""
  echo "=== SUCCESS ==="
  echo "  node_exporter  : http://${INTERNAL_IP}:9100/metrics"
  echo "  mysqld_exporter: http://${INTERNAL_IP}:9104/metrics"
  echo ""
  echo "  Next steps:"
  echo "  1. Replace DB_REPLICA_IP in prometheus.prod.yml with: ${INTERNAL_IP}"
  echo "  2. Reload Prometheus: docker kill -s HUP prometheus"
else
  echo "=== ERROR: mysqld_exporter started but MySQL reports mysql_up != 1 ==="
  echo "  Likely cause: wrong MYSQL_ROOT_PASS or monitoring user creation failed"
  echo "  Check: journalctl -u mysqld_exporter -n 30"
  exit 1
fi
