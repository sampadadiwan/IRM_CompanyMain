#!/usr/bin/env bash
# Starts the data-tier containers (Elasticsearch + Redis) on the DB server.
# Called from the ubuntu user's @reboot crontab, baked into the DB AMI by
# Packer (db_redis_es.ami.pkr.hcl), and installed on live boxes by
# rake "ops:data_box_limits[<env>]" (lib/tasks/data_box_limits.rake).
#
# WHY THIS SCRIPT EXISTS: a raw `@reboot docker run ...` crontab line RACES
# the docker daemon — cron fires @reboot before docker.service is up, the run
# dies instantly, and --rm leaves no evidence. Found on the first fresh-AMI
# DR drill (2026-07-10): box up 30+ minutes, no containers, empty docker ps -a.
#
# MEMORY LIMITS (2026-11-09): without them Elasticsearch auto-sizes its heap to
# ~50% of the box's RAM (3.9 GB on prod IN, for 117 MB of live data) and Redis
# has no maxmemory. Both come from /etc/default/irm-data-containers, written by
# the rake task from the box's own peak usage (rule in lib/data_box_limits.rb);
# the defaults below are that rule's floor, for a fresh AMI / DR box.
#
# Idempotent — safe to run manually at any time:
#   /usr/local/bin/start_data_containers.sh
set -u

log() { logger -t start_data_containers "$*"; echo "$(date -Is) $*"; }

# Per-box limits (rake ops:data_box_limits); floor values when the file is absent
ES_HEAP=512m
ES_MEMORY=1536m
REDIS_MAXMEMORY=512mb
# shellcheck source=/dev/null
[ -r /etc/default/irm-data-containers ] && . /etc/default/irm-data-containers

# Wait up to 5 minutes for the docker daemon (the whole point of this script)
for _ in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sudo -n docker info >/dev/null 2>&1 && break
  sleep 5
done
# ubuntu is in the docker group on AMI-built boxes; older boxes need sudo
if docker info >/dev/null 2>&1; then
  DOCKER="docker"
elif sudo -n docker info >/dev/null 2>&1; then
  DOCKER="sudo -n docker"
else
  log "ERROR: docker daemon not up after 300s — data containers NOT started"
  exit 1
fi

# running / stopped / absent, for a container name
state() {
  if $DOCKER ps --format '{{.Names}}' | grep -qx "$1"; then echo running
  elif $DOCKER ps -a --format '{{.Names}}' | grep -qx "$1"; then echo stopped
  else echo absent; fi
}

# Images are pre-pulled at AMI bake time, so these starts need no network.
# Keep tags in sync with the `docker pull` lines in db_redis_es.ami.pkr.hcl
# and DataBoxLimits::ES_IMAGE.
#
# Elasticsearch: the index lives in the elasticsearch-data volume, so a restart
# keeps it; --restart unless-stopped lets dockerd bring it back after a crash or
# a reboot (before cron even runs). A stopped container keeps its name, so it is
# started again rather than re-created.
case "$(state elasticsearch)" in
  running) ;;
  stopped)
    log "starting existing elasticsearch container"
    $DOCKER start elasticsearch ;;
  absent)
    log "creating elasticsearch (heap $ES_HEAP, memory cap $ES_MEMORY, volume elasticsearch-data)"
    $DOCKER run -d \
      --name elasticsearch \
      --restart unless-stopped \
      --memory="$ES_MEMORY" \
      -p 9200:9200 \
      -p 9300:9300 \
      -v elasticsearch-data:/usr/share/elasticsearch/data \
      -e ES_JAVA_OPTS="-Xms$ES_HEAP -Xmx$ES_HEAP" \
      -e "discovery.type=single-node" \
      -e "xpack.security.enabled=false" \
      elasticsearch:8.19.0 ;;
esac

# Redis: holds Sidekiq's queues. maxmemory caps it; noeviction because evicting
# would silently drop jobs (at the limit Redis refuses writes instead).
# Still --rm and no volume: changing that needs a Redis restart, which loses the
# queues — a separate, scheduled step.
case "$(state redis-stack-server)" in
  running) ;;
  stopped)
    log "starting existing redis-stack-server container"
    $DOCKER start redis-stack-server ;;
  absent)
    log "creating redis-stack-server (maxmemory $REDIS_MAXMEMORY, noeviction)"
    $DOCKER run -d --rm --name redis-stack-server -p 6379:6379 \
      -e REDIS_ARGS="--maxmemory $REDIS_MAXMEMORY --maxmemory-policy noeviction" \
      redis/redis-stack-server:latest ;;
esac

log "data containers running: $($DOCKER ps --format '{{.Names}}' | tr '\n' ' ')"
