#!/bin/bash
#
# Clean shutdown for the Sidekiq process monit supervises. Installed to
# #{shared_path}/bin/sidekiq_stop.sh by IRM:setup and invoked from the
# `stop program` line of config/deploy/monit/sidekiq_IRM_env.conf.erb.
#
# Why this exists as a script rather than a one-liner in the monit config:
#
#   The previous stop program was `... | xargs kill` with `with timeout 10
#   seconds`. That sends a bare SIGTERM and never escalates. Sidekiq's SIGTERM
#   handler is a GRACEFUL shutdown that waits up to its -t timeout (25s by
#   default, and we set no sidekiq.yml) for in-flight jobs to finish. So monit
#   gave up at 10 seconds while Sidekiq was still legitimately draining, decided
#   the stop had failed, and ran the start program anyway — leaving TWO Sidekiq
#   processes on the box. Staging then compounded it: keep_releases is 1 there
#   (config/deploy.rb), so deploy:cleanup deletes the survivor's release
#   directory out from under it. Ruby resolves the `current` symlink to a
#   physical path at boot, so Zeitwerk's autoload index still points into the
#   deleted directory and every LAZY constant load in that process starts
#   raising `cannot load such file`. Classes already in memory keep working,
#   which is why the box looks healthy while specific jobs fail.
#
#   Worse, monit's `matching 'sidekiq .* '` matched the orphan, so monit
#   reported the service OK and never started a replacement. One broken worker
#   was silently serving the whole queue.
#
# Exits 0 whenever no Sidekiq remains, so monit sees a successful stop.
set -u

# Anchored deliberately. Sidekiq sets its proctitle to "sidekiq 8.1.7 IRM [0 of
# 7 busy]", so ^sidekiq matches the real workers and nothing else — in
# particular NOT this script (argv[0] is bash) and not the `su` that spawned it.
# An unanchored "sidekiq" would match both and the script would kill itself.
PATTERN='^sidekiq '

# Must stay comfortably above Sidekiq's own -t shutdown timeout (25s default),
# and the monit `with timeout` on the stop program must stay above THIS.
GRACE=${SIDEKIQ_STOP_GRACE:-45}

running_pids() {
  pgrep -f "$PATTERN" || true
}

pids=$(running_pids)
if [ -z "$pids" ]; then
  echo "sidekiq_stop: nothing running"
  exit 0
fi

echo "sidekiq_stop: SIGTERM to $(echo "$pids" | tr '\n' ' ')"
# shellcheck disable=SC2086 # word splitting is intended: kill takes a pid list
kill -TERM $pids 2>/dev/null || true

waited=0
while [ "$waited" -lt "$GRACE" ]; do
  sleep 1
  waited=$((waited + 1))
  if [ -z "$(running_pids)" ]; then
    echo "sidekiq_stop: drained cleanly after ${waited}s"
    exit 0
  fi
done

# Past the grace period the process is either wedged or running a job that will
# never finish. Either way it must not survive into the next release, because a
# survivor is exactly what orphans itself against a deleted release directory.
survivors=$(running_pids)
if [ -n "$survivors" ]; then
  echo "sidekiq_stop: still alive after ${GRACE}s, SIGKILL to $(echo "$survivors" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  kill -KILL $survivors 2>/dev/null || true
  sleep 2
fi

remaining=$(running_pids)
if [ -n "$remaining" ]; then
  echo "sidekiq_stop: FAILED, pids still present: $(echo "$remaining" | tr '\n' ' ')" >&2
  exit 1
fi

echo "sidekiq_stop: stopped"
exit 0
