# frozen_string_literal: true

require "json"
require "active_support/core_ext/object/blank" # presence

# Memory limits for the data box's Elasticsearch and Redis, and the pure decisions around applying
# them — used by `rake "ops:data_box_limits[<env>]"` (lib/tasks/data_box_limits.rake) and
# features/misc/data_box_limits.feature.
#
# Why: the IN data box (7.66 GiB, MySQL + Elasticsearch + Redis) sat at ~85% memory. Prometheus
# (2026-11-09, 43 days of JVM / Redis uptime) showed Elasticsearch holding a 3.9 GB heap it had
# auto-sized to half the RAM — for 117.5 MB of live data, 0 old-generation GCs — and Redis peaking
# at 4.2 MB with no maxmemory at all. Both are sized by ONE rule, agreed 2026-11-09:
#
#   limit = max(3 x peak usage, 512 MB)
#
# - Elasticsearch: peak usage = old-generation peak since JVM start (data that survives GC).
#   Container cap = max(2 x heap, heap + 1 GB): heap + non-heap (~260 MB) + direct memory (up to
#   half the heap) must fit with margin, and Elastic's guidance is heap <= half the container.
#   512 MB heap -> 1536 MB cap.
# - Redis: peak usage = used_memory_peak since Redis start. noeviction, because Redis holds
#   Sidekiq's jobs: at the limit a write is refused rather than a job silently dropped.
#
# Pure: no SSH, no Docker. The rake task fetches text from the box and acts on the answers.
module DataBoxLimits
  MB = 1_048_576
  FLOOR_BYTES = 512 * MB
  PEAK_FACTOR = 3
  # Heap is rounded up to a multiple of this (JVM-friendly sizes)
  HEAP_STEP_MB = 128
  # The container cap's minimum headroom above the heap
  CONTAINER_HEADROOM_MB = 1024

  # Environments the task may change. Staging first, then production IN (decision 2026-11-09).
  ENVS = %w[staging.in production.in production.us].freeze

  # Must match config/deploy/templates/packer/start_data_containers.sh
  ES_CONTAINER = "elasticsearch"
  ES_IMAGE = "elasticsearch:8.19.0"
  ES_VOLUME = "elasticsearch-data"
  ES_DATA_DIR = "/usr/share/elasticsearch/data"
  REDIS_CONTAINER = "redis-stack-server"
  # The data containers the task sizes — always together, as the start script starts them
  DATA_CONTAINERS = [ES_CONTAINER, REDIS_CONTAINER].freeze
  # Environment the start script gives Elasticsearch; any OTHER setting on the live container would
  # be lost by recreating it, so the task refuses until the script carries it too
  ES_SCRIPT_ENV_KEYS = %w[ES_JAVA_OPTS discovery.type xpack.security.enabled].freeze

  SCRIPT_PATH = "/usr/local/bin/start_data_containers.sh"
  SCRIPT_REPO_PATH = "config/deploy/templates/packer/start_data_containers.sh"
  # Per-box limits the start script reads on every boot
  DEFAULTS_PATH = "/etc/default/irm-data-containers"
  # The boot line the AMI bakes (db_redis_es.ami.pkr.hcl) — the script waits for dockerd
  SCRIPT_CRON_LINE = "@reboot #{SCRIPT_PATH} >> /home/ubuntu/start_data_containers.log 2>&1".freeze
  # An old raw boot line that starts one of the data containers itself (races dockerd at boot)
  RAW_CONTAINER_LINE = /\A\s*@reboot\b.*\bdocker\s+run\b.*--name[ =](?:elasticsearch|redis-stack-server)\b/

  module_function

  def env_allowed?(env_name)
    ENVS.include?(env_name.to_s)
  end

  # --- Which boxes -------------------------------------------------------------------------------

  # The boxes the task works on, data box first. Each entry is { host:, role:, status:, reason: }
  # with role :data_box / :replica and status :apply / :skip / :refuse.
  #
  # - The data box (where ELASTIC_SEARCH_URL / REDIS_URL point) is always worked on.
  # - The MySQL replica too, when it runs its own Elasticsearch and Redis: on prod IN (2026-11-10)
  #   it does — they are the DR standby that dr:fix_db repoints the app to — and left uncapped they
  #   blocked ops:mysql_buffer_pool on that box ("Redis has no maxmemory").
  # - A replica running MySQL only (prod US) is skipped: nothing to cap.
  # - A replica running just one of the two is refused: the start script starts both, so
  #   installing it there would add a container nobody asked for.
  # replica_containers: the names `docker ps` lists on the replica.
  def target_boxes(data_box:, replica:, replica_containers:)
    # H — the data box: always
    boxes = [{ host: data_box, role: :data_box, status: :apply }]
    # E — no replica, or staging's "replica" is the data box itself
    return boxes if replica.to_s.empty? || replica == data_box

    running = Array(replica_containers) & DATA_CONTAINERS
    boxes << if running.empty?
               # E — prod US: MySQL only
               { host: replica, role: :replica, status: :skip, reason: "runs no Elasticsearch or Redis (MySQL only) - nothing to cap" }
             elsif running.size < DATA_CONTAINERS.size
               # X — half a standby: not ours to complete
               { host: replica, role: :replica, status: :refuse,
                 reason: "runs only #{running.join(', ')} - the start script starts both; cap it by hand or remove it" }
             else
               # H — prod IN: the DR standby
               { host: replica, role: :replica, status: :apply }
             end
    boxes
  end

  # Queue the search reindex after re-creating Elasticsearch? Only on the data box, and only when
  # the old index lived inside the container (so it is gone). The replica's Elasticsearch is a
  # standby the app does not read; a failover rebuilds the indexes anyway (dr:fix_db step list).
  def reindex_needed?(role:, drift:, volume:)
    role == :data_box && drift.any? && volume != ES_VOLUME
  end

  # --- Sizing ----------------------------------------------------------------------------------

  # max(3 x peak, 512 MB) in bytes
  def limit_bytes(peak_bytes)
    [PEAK_FACTOR * peak_bytes.to_i, FLOOR_BYTES].max
  end

  # Elasticsearch heap in MB from the old-generation peak, rounded up to HEAP_STEP_MB
  def es_heap_mb(old_gen_peak_bytes)
    mb = (limit_bytes(old_gen_peak_bytes) / MB.to_f).ceil
    (mb / HEAP_STEP_MB.to_f).ceil * HEAP_STEP_MB
  end

  # The container's memory cap for a heap
  def es_container_mb(heap_mb)
    [2 * heap_mb, heap_mb + CONTAINER_HEADROOM_MB].max
  end

  # Redis maxmemory in bytes from used_memory_peak, rounded up to a whole MB
  def redis_maxmemory_bytes(used_peak_bytes)
    (limit_bytes(used_peak_bytes) / MB.to_f).ceil * MB
  end

  # --- Reading the box ---------------------------------------------------------------------------

  # `redis-cli INFO memory` -> { used_memory:, used_memory_peak:, maxmemory:, maxmemory_policy: }
  def parse_redis_info(text)
    fields = text.to_s.lines.filter_map { |l| l.strip.split(":", 2) if l.include?(":") }.to_h
    {
      used_memory: fields["used_memory"].to_i,
      used_memory_peak: fields["used_memory_peak"].to_i,
      maxmemory: fields["maxmemory"].to_i,
      maxmemory_policy: fields["maxmemory_policy"].to_s
    }
  end

  # `GET _nodes/stats/jvm` -> { heap_max:, old_used:, old_peak:, uptime_s: } for the (single) node,
  # or nil when Elasticsearch did not answer with JSON
  def parse_es_jvm(json_text)
    node = JSON.parse(json_text.to_s).fetch("nodes", {}).values.first
    return nil unless node

    jvm = node["jvm"] || {}
    old = jvm.dig("mem", "pools", "old") || {}
    { heap_max: jvm.dig("mem", "heap_max_in_bytes").to_i, old_used: old["used_in_bytes"].to_i,
      old_peak: old["peak_used_in_bytes"].to_i, uptime_s: jvm["uptime_in_millis"].to_i / 1000 }
  rescue JSON::ParserError
    nil
  end

  # `docker inspect <es>` + `docker image inspect <image>` -> the container's current shape.
  # user_env: settings given to the container, not inherited from the image.
  def es_container_state(container_json, image_json)
    container = Array(JSON.parse(container_json.to_s)).first
    return nil unless container

    image_env = Array(Array(JSON.parse(image_json.to_s)).first&.dig("Config", "Env"))
    env = Array(container.dig("Config", "Env")) - image_env
    data_mount = Array(container["Mounts"]).find { |m| m["Destination"] == ES_DATA_DIR }
    {
      image: container.dig("Config", "Image").to_s,
      memory_mb: container.dig("HostConfig", "Memory").to_i / MB,
      restart: container.dig("HostConfig", "RestartPolicy", "Name").to_s,
      auto_remove: container.dig("HostConfig", "AutoRemove") == true,
      volume: data_mount && data_mount["Type"] == "volume" ? data_mount["Name"].to_s : nil,
      user_env: env.to_h { |kv| kv.split("=", 2) }
    }
  rescue JSON::ParserError
    nil
  end

  # What differs between the live container and the target — empty means nothing to recreate
  def es_drift(state, heap_mb:, container_mb:)
    reasons = []
    reasons << "memory cap #{state[:memory_mb].zero? ? 'none' : "#{state[:memory_mb]} MB"} -> #{container_mb} MB" if state[:memory_mb] != container_mb
    heap = state[:user_env]["ES_JAVA_OPTS"].to_s
    reasons << "heap #{heap.empty? ? 'auto (~50% of RAM)' : heap} -> -Xms#{heap_mb}m -Xmx#{heap_mb}m" unless heap.include?("-Xmx#{heap_mb}m")
    reasons << "restart policy #{state[:auto_remove] ? '--rm' : state[:restart].presence || 'none'} -> unless-stopped" if state[:restart] != "unless-stopped"
    reasons << "data #{state[:volume] ? "volume #{state[:volume]}" : 'inside the container (lost on restart)'} -> volume #{ES_VOLUME}" if state[:volume] != ES_VOLUME
    reasons
  end

  # Must an existing elasticsearch-data volume be moved aside before re-creating? Yes when the
  # volume exists but the live container does not use it: its contents are left over from an
  # earlier container, and the new one would start on them. Prod US (2026-11-09) had one holding
  # 27 indexes from 1 September - search would have served two-month-old results until the
  # reindex replaced them. Moved, not deleted: the copy is kept as elasticsearch-data-stale-<stamp>.
  def stale_volume?(state, volume_exists:)
    volume_exists && state[:volume] != ES_VOLUME
  end

  # Why recreating the live container would be unsafe, or nil when it is safe
  def es_recreate_refusal(state)
    # A different image could not read the index / would change versions on the side
    return "live container runs #{state[:image]}, the start script pins #{ES_IMAGE} — align them first" if state[:image] != ES_IMAGE

    # Settings the start script does not give would silently disappear
    extra = state[:user_env].keys - ES_SCRIPT_ENV_KEYS
    return "live container has settings the start script does not set (#{extra.join(', ')}) — add them to #{SCRIPT_REPO_PATH} first" if extra.any?

    nil
  end

  # The per-box limits file the start script sources at boot
  def defaults_file(heap_mb:, container_mb:, redis_maxmemory_bytes:)
    <<~ENV
      # Written by rake ops:data_box_limits (lib/data_box_limits.rb) — read by #{SCRIPT_PATH} at boot.
      # Rule: max(3 x peak usage, 512 MB). Re-run the rake task to re-size; do not hand-edit.
      ES_HEAP=#{heap_mb}m
      ES_MEMORY=#{container_mb}m
      REDIS_MAXMEMORY=#{redis_maxmemory_bytes / MB}mb
    ENV
  end

  # Replaces the old raw `@reboot docker run` lines with the start script's line. Every other line
  # is kept. Returns { status: :changed / :unchanged, text:, removed: [...] }.
  def crontab_plan(text)
    # `crontab -l` for a user with none prints "no crontab for <user>" - that is not a line
    lines = text.to_s.lines.map(&:chomp).grep_v(/\Ano crontab for /)
    removed, kept = lines.partition { |l| l.match?(RAW_CONTAINER_LINE) }
    has_script = kept.any? { |l| l.strip == SCRIPT_CRON_LINE }
    return { status: :unchanged, text: text, removed: [] } if removed.empty? && has_script

    kept << SCRIPT_CRON_LINE unless has_script
    { status: :changed, text: "#{kept.join("\n")}\n", removed: removed }
  end
end
