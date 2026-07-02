#!/bin/bash
# SSL certificate expiry check — pushes days_remaining to Prometheus Pushgateway.
#
# Setup:
#   1. Copy this script to the app server: /opt/scripts/ssl_cert_check.sh
#   2. chmod +x /opt/scripts/ssl_cert_check.sh
#   3. Add a cron job (runs hourly):
#      0 * * * * /opt/scripts/ssl_cert_check.sh >> /var/log/ssl_cert_check.log 2>&1
#
# Requirements:
#   - openssl
#   - curl
#   - A Prometheus Pushgateway accessible at PUSHGATEWAY_URL (or node_exporter textfile collector)
#
# If you don't have a Pushgateway, use the textfile collector instead:
#   Set OUTPUT_MODE=textfile and TEXTFILE_DIR to node_exporter's --collector.textfile.directory
#
# The Grafana alert rules in grafana_provision.yml query the metric: ssl_cert_days_remaining

DOMAIN="${DOMAIN:-app.caphive.com}"
PORT="${PORT:-443}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://localhost:9091}"
OUTPUT_MODE="${OUTPUT_MODE:-pushgateway}"   # pushgateway | textfile
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
JOB_NAME="ssl_cert_check"

# Query the certificate's expiry date
EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:$PORT" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null \
  | cut -d= -f2)

if [ -z "$EXPIRY" ]; then
  echo "[$(date)] ERROR: Could not retrieve certificate for $DOMAIN:$PORT"
  exit 1
fi

# Calculate days remaining (BSD and GNU date compatible)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" +%s)
NOW_EPOCH=$(date +%s)
DAYS_REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

echo "[$(date)] $DOMAIN expires in $DAYS_REMAINING days ($EXPIRY)"

METRIC_TEXT="# HELP ssl_cert_days_remaining Days until SSL certificate expires
# TYPE ssl_cert_days_remaining gauge
ssl_cert_days_remaining{domain=\"$DOMAIN\"} $DAYS_REMAINING
"

if [ "$OUTPUT_MODE" = "textfile" ]; then
  # node_exporter textfile collector mode — no Pushgateway needed
  echo "$METRIC_TEXT" > "$TEXTFILE_DIR/ssl_cert.prom"
  echo "[$(date)] Written to $TEXTFILE_DIR/ssl_cert.prom"
else
  # Push to Prometheus Pushgateway
  echo "$METRIC_TEXT" | curl --silent --fail \
    --data-binary @- \
    "$PUSHGATEWAY_URL/metrics/job/$JOB_NAME/instance/$DOMAIN"
  if [ $? -eq 0 ]; then
    echo "[$(date)] Pushed to $PUSHGATEWAY_URL"
  else
    echo "[$(date)] ERROR: Failed to push to $PUSHGATEWAY_URL"
    exit 1
  fi
fi
