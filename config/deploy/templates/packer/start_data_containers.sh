#!/usr/bin/env bash
# Starts the data-tier containers (Elasticsearch + Redis) on the DB server.
# Called from the ubuntu user's @reboot crontab, baked into the DB AMI by
# Packer (db_redis_es.ami.pkr.hcl).
#
# WHY THIS SCRIPT EXISTS: a raw `@reboot docker run ...` crontab line RACES
# the docker daemon — cron fires @reboot before docker.service is up, the run
# dies instantly, and --rm leaves no evidence. Found on the first fresh-AMI
# DR drill (2026-07-10): box up 30+ minutes, no containers, empty docker ps -a.
#
# Idempotent — safe to run manually at any time:
#   /usr/local/bin/start_data_containers.sh
set -u

log() { logger -t start_data_containers "$*"; echo "$(date -Is) $*"; }

# Wait up to 5 minutes for the docker daemon (the whole point of this script)
for _ in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 5
done
if ! docker info >/dev/null 2>&1; then
  log "ERROR: docker daemon not up after 300s — data containers NOT started"
  exit 1
fi

# Images are pre-pulled at AMI bake time, so these starts need no network.
# Keep tags in sync with the `docker pull` lines in db_redis_es.ami.pkr.hcl.
if ! docker ps --format '{{.Names}}' | grep -qx elasticsearch; then
  log "starting elasticsearch"
  docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 \
    -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
    -e "discovery.type=single-node" -e "xpack.security.enabled=false" \
    elasticsearch:8.19.0
fi

if ! docker ps --format '{{.Names}}' | grep -qx redis-stack-server; then
  log "starting redis-stack-server"
  docker run -d --rm --name redis-stack-server -p 6379:6379 \
    redis/redis-stack-server:latest
fi

log "data containers running: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
