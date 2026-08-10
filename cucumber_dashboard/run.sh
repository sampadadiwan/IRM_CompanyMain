#!/usr/bin/env bash
# Cucumber Dashboard — launch modes:
#   ./run.sh                  — Start dashboard server only (runs are triggered from the UI)
#   ./run.sh features/ -n 4   — Start dashboard + immediately run parallel_cucumber

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROGRESS_DIR="/tmp/cucumber_progress"

# Clean previous run
rm -rf "$PROGRESS_DIR"
mkdir -p "$PROGRESS_DIR"

if [ $# -eq 0 ]; then
  # Server-only mode — runs are started from the dashboard UI
  echo ""
  echo "  Starting Cucumber Dashboard server..."
  echo "  Open http://localhost:9777 to configure and start runs"
  echo ""
  ruby "$SCRIPT_DIR/dashboard_server.rb"
else
  # Direct run mode — start server + run cucumber immediately
  FEATURE_DIR="${1:-features/}"
  TOTAL_SCENARIOS=$(grep -r -c "Scenario" "$FEATURE_DIR" --include="*.feature" 2>/dev/null | awk -F: '{s+=$2} END {print s}')
  echo "$TOTAL_SCENARIOS" > "$PROGRESS_DIR/total_scenarios"

  echo ""
  echo "  Total scenarios detected: $TOTAL_SCENARIOS"
  echo "  Starting Cucumber Dashboard server..."
  echo ""

  ruby "$SCRIPT_DIR/dashboard_server.rb" &
  DASHBOARD_PID=$!
  sleep 1

  CUCUMBER_ARGS="$@"

  echo "  Running: RUBYOPT='-W0' bundle exec parallel_cucumber $CUCUMBER_ARGS"
  echo "  Dashboard: http://localhost:9777"
  echo ""

  RUBYOPT='-W0' bundle exec parallel_cucumber $CUCUMBER_ARGS \
    -o "--require features --require $SCRIPT_DIR --format CucumberDashboard::ProgressFormatter --out /dev/null" \
    2>&1 | tee /tmp/cucumber_full_output.txt || true

  EXIT_CODE=${PIPESTATUS[0]}

  echo ""
  echo "  Run complete. Dashboard still live at http://localhost:9777"
  echo "  Press Ctrl+C to stop the dashboard server."
  echo ""

  wait $DASHBOARD_PID 2>/dev/null || true
  exit $EXIT_CODE
fi
