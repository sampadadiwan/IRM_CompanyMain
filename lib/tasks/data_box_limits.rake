# frozen_string_literal: true

# Caps the data box's Elasticsearch and Redis memory, gives Elasticsearch a data volume and a
# restart policy, and makes all of it survive a reboot — for staging, then production.
#
#   rake "ops:data_box_limits[staging.in]"             # dry run: measures, prints the plan, changes nothing
#   EXECUTE=1 rake "ops:data_box_limits[staging.in]"   # applies, verifies, prints the rollback
#
# Sizing rule and why: lib/data_box_limits.rb (max(3 x peak usage, 512 MB), from the box's own
# Elasticsearch old-generation peak and Redis used_memory_peak).
#
# Which boxes (DataBoxLimits.target_boxes): the data box, and the MySQL replica too when it runs its
# own Elasticsearch + Redis (prod IN's DR standby, 2026-11-10). A MySQL-only replica (prod US) is
# skipped. Every box is measured and planned first, read-only; nothing changes until all plans pass.
#
# What EXECUTE does on each box, data box first (a failure there stops before the replica):
#   1. installs the repo's start_data_containers.sh and /etc/default/irm-data-containers (limits)
#   2. swaps the old raw `@reboot docker run` crontab lines for the script's line (crontab saved)
#   3. Redis: CONFIG SET maxmemory + noeviction — live, NO restart (a restart would lose Sidekiq's
#      queues: Redis has no volume)
#   4. Elasticsearch: only if it differs from the target — stop, re-create through the script
#      (memory cap, heap, elasticsearch-data volume, --restart unless-stopped), wait for health
# then, once:
#   5. queues the search reindex when the data box's old index lived inside the container (it is
#      gone). Never for the replica: its Elasticsearch is a standby the app does not read.
#
# Elasticsearch is DOWN for ~1-2 minutes in step 4 and search results are incomplete until the
# reindex job finishes — on production, run it in a quiet window. Refuses (before touching
# anything) when a live container runs another image or carries settings the script lacks.
#
# Reaches the boxes through an app server, like observability:data_box_exporters (dbx_remote).

require "base64"
require "digest"
require "json"
require "open3"

# "117.5 MB"
def dbl_mb(bytes)
  "#{(bytes / DataBoxLimits::MB.to_f).round(1)} MB"
end

# One box's memory line, e.g. "box memory: 4679 MB available of 7840 MB"
def dbl_mem_line(run, label)
  puts "   #{label}: #{run.call("free -m | awk '/^Mem:/ {printf \"%d MB available of %d MB\", $7, $2}'")}"
end

# Measure one box and work out its plan — read-only. Aborts (nothing touched yet, on any box) when
# the box cannot be read. Returns everything dbl_apply_box needs.
def dbl_plan_box(run, target, stamp)
  host = target[:host]
  label = target[:role] == :replica ? "replica - DR standby" : "data box"
  puts "\n📋 #{host} (#{label})"
  dbl_mem_line(run, "box memory")

  # 1. Measure Redis and Elasticsearch on this box
  redis = DataBoxLimits.parse_redis_info(run.call("sudo docker exec #{DataBoxLimits::REDIS_CONTAINER} redis-cli INFO memory"))
  abort "❌ Could not read Redis INFO from #{DataBoxLimits::REDIS_CONTAINER} on #{host}. Nothing touched." if redis[:used_memory_peak].zero?

  jvm = DataBoxLimits.parse_es_jvm(run.call("curl -s http://localhost:9200/_nodes/stats/jvm"))
  abort "❌ Elasticsearch on #{host}:9200 did not return JVM stats. Nothing touched." unless jvm

  container_json = run.call("sudo docker inspect #{DataBoxLimits::ES_CONTAINER}")
  image = begin
    Array(JSON.parse(container_json)).first&.dig("Config", "Image").to_s
  rescue JSON::ParserError
    ""
  end
  es = DataBoxLimits.es_container_state(container_json, run.call("sudo docker image inspect #{image}"))
  abort "❌ No #{DataBoxLimits::ES_CONTAINER} container on #{host}. Nothing touched." unless es

  puts "   Elasticsearch: heap #{dbl_mb(jvm[:heap_max])}, live data (old gen) now #{dbl_mb(jvm[:old_used])}, " \
       "peak #{dbl_mb(jvm[:old_peak])} over #{(jvm[:uptime_s] / 86_400.0).round(1)} days"
  puts "   Elasticsearch container: #{es[:image]}, memory cap #{es[:memory_mb].zero? ? 'none' : "#{es[:memory_mb]} MB"}, " \
       "#{es[:auto_remove] ? '--rm' : "restart=#{es[:restart].presence || 'no'}"}, data #{es[:volume] ? "in volume #{es[:volume]}" : 'inside the container'}"
  puts "   Redis: used #{dbl_mb(redis[:used_memory])}, peak #{dbl_mb(redis[:used_memory_peak])}, " \
       "maxmemory #{redis[:maxmemory].zero? ? 'unlimited' : dbl_mb(redis[:maxmemory])} (#{redis[:maxmemory_policy]})"

  # 2. Size from this box's own measurements: max(3 x peak, 512 MB)
  heap_mb = DataBoxLimits.es_heap_mb(jvm[:old_peak])
  container_mb = DataBoxLimits.es_container_mb(heap_mb)
  redis_max = DataBoxLimits.redis_maxmemory_bytes(redis[:used_memory_peak])
  puts "   Limits = max(3 x peak, 512 MB): Elasticsearch heap #{heap_mb} MB, container cap #{container_mb} MB; " \
       "Redis maxmemory #{redis_max / DataBoxLimits::MB} MB, noeviction"

  # 3. The plan for this box
  drift = DataBoxLimits.es_drift(es, heap_mb: heap_mb, container_mb: container_mb)
  refusal = DataBoxLimits.es_recreate_refusal(es)
  cron = DataBoxLimits.crontab_plan(run.call("crontab -l 2>&1"))
  defaults = DataBoxLimits.defaults_file(heap_mb: heap_mb, container_mb: container_mb, redis_maxmemory_bytes: redis_max)
  script = Rails.root.join(DataBoxLimits::SCRIPT_REPO_PATH).read
  script_current = run.call("sha256sum #{DataBoxLimits::SCRIPT_PATH} 2>/dev/null | cut -d' ' -f1") == Digest::SHA256.hexdigest(script)
  reindex = DataBoxLimits.reindex_needed?(role: target[:role], drift: drift, volume: es[:volume])
  # A volume of that name the live container does not use holds an earlier container's index
  volume_exists = run.call("sudo docker volume inspect #{DataBoxLimits::ES_VOLUME} >/dev/null 2>&1 && echo EXISTS").include?("EXISTS")
  stale = drift.any? && DataBoxLimits.stale_volume?(es, volume_exists: volume_exists)
  stale_aside = "#{DataBoxLimits::ES_VOLUME}-stale-#{stamp}"
  stale_detail = stale ? run.call(<<~BASH).strip : ""
    mp=$(sudo docker volume inspect #{DataBoxLimits::ES_VOLUME} --format '{{.Mountpoint}}')
    users=$(sudo docker ps -a --filter volume=#{DataBoxLimits::ES_VOLUME} --format '{{.Names}}' | tr '\n' ' ')
    echo "$(sudo du -sh "$mp" | cut -f1), last written $(sudo find "$mp" -type f -printf '%TY-%Tm-%Td\n' | sort | tail -1), used by: ${users:-no container}"
  BASH

  puts "   🗺  Plan"
  puts "   • #{script_current ? 'start script already current' : "install #{DataBoxLimits::SCRIPT_PATH} from the repo"}; write #{DataBoxLimits::DEFAULTS_PATH}"
  puts "   • crontab: #{cron[:status] == :unchanged ? 'already uses the start script' : "replace #{cron[:removed].size} raw @reboot line(s) with the start script"}"
  cron[:removed].each { |l| puts "       - #{l}" }
  puts "   • Redis: CONFIG SET maxmemory #{redis_max} (#{redis_max / DataBoxLimits::MB} MB) + noeviction — live, no restart"
  if drift.empty?
    puts "   • Elasticsearch: already at the target — not touched"
  else
    down = target[:role] == :replica ? "standby only - the app does not read it; no reindex" : "DOWN ~1-2 min"
    puts "   • Elasticsearch: re-create (#{down}#{'; index rebuilt by the reindex job' if reindex})"
    drift.each { |d| puts "       - #{d}" }
  end
  if stale
    puts "   • Elasticsearch: an unused #{DataBoxLimits::ES_VOLUME} volume already exists (#{stale_detail}) — " \
         "moved aside to #{stale_aside} BEFORE Elasticsearch stops, so the new container starts empty"
  end
  puts "   ⛔ Elasticsearch cannot be re-created: #{refusal}" if drift.any? && refusal

  { host: host, role: target[:role], redis: redis, heap_mb: heap_mb, container_mb: container_mb, redis_max: redis_max,
    drift: drift, refusal: drift.any? ? refusal : nil, cron: cron, defaults: defaults, script: script,
    reindex: reindex, stale: stale, stale_aside: stale_aside }
end

# Apply one box's plan. Returns { rollback: [...], failures: [...], reindex: true/false }.
def dbl_apply_box(run, plan, stamp)
  host = plan[:host]
  rollback = []
  failures = []
  drift = plan[:drift]
  reindex = plan[:reindex]
  puts "\n🔧 #{host} (#{plan[:role] == :replica ? 'replica' : 'data box'})"

  # 1. Start script + limits file. The old limits file (if any) is kept beside the new one.
  out = run.call(<<~BASH)
    set -euo pipefail
    echo #{Base64.strict_encode64(plan[:script])} | base64 -d > /tmp/start_data_containers.sh
    sudo install -m 0755 -o root -g root /tmp/start_data_containers.sh #{DataBoxLimits::SCRIPT_PATH}
    rm -f /tmp/start_data_containers.sh
    if [ -f #{DataBoxLimits::DEFAULTS_PATH} ]; then sudo cp -p #{DataBoxLimits::DEFAULTS_PATH} #{DataBoxLimits::DEFAULTS_PATH}.bak-#{stamp}; fi
    echo #{Base64.strict_encode64(plan[:defaults])} | base64 -d | sudo tee #{DataBoxLimits::DEFAULTS_PATH} >/dev/null
    sudo chmod 0644 #{DataBoxLimits::DEFAULTS_PATH}
    echo INSTALLED
  BASH
  return { rollback: rollback, failures: ["#{host}: installing the start script / limits file failed: #{out.strip.lines.last}"], reindex: false } unless out.include?("INSTALLED")

  puts "✅ start script and #{DataBoxLimits::DEFAULTS_PATH} installed"

  # 2. Crontab: save, write, re-read to prove it
  if plan[:cron][:status] == :changed
    saved = "~/crontab.before-data-box-limits.#{stamp}"
    written = run.call("crontab -l > #{saved} 2>/dev/null; echo #{Base64.strict_encode64(plan[:cron][:text])} | base64 -d | crontab - && echo OK")
    verdict = DataBoxLimits.crontab_plan(run.call("crontab -l 2>&1"))
    if written.include?("OK") && verdict[:status] == :unchanged
      puts "✅ crontab: boots through the start script (old crontab saved to #{saved})"
      rollback << "#{host} crontab: crontab #{saved}"
    else
      failures << "#{host}: crontab not updated (#{written.strip}) — saved copy #{saved}"
    end
  end

  # 3. Redis: live limit, no restart — then read it back
  redis_cli = "sudo docker exec #{DataBoxLimits::REDIS_CONTAINER} redis-cli"
  before = plan[:redis]
  run.call("#{redis_cli} CONFIG SET maxmemory #{plan[:redis_max]} && #{redis_cli} CONFIG SET maxmemory-policy noeviction")
  after = DataBoxLimits.parse_redis_info(run.call("#{redis_cli} INFO memory"))
  if after[:maxmemory] == plan[:redis_max] && after[:maxmemory_policy] == "noeviction"
    puts "✅ Redis: maxmemory #{plan[:redis_max] / DataBoxLimits::MB} MB, noeviction (used #{dbl_mb(after[:used_memory])})"
    rollback << "#{host} Redis: #{redis_cli} CONFIG SET maxmemory #{before[:maxmemory]} && #{redis_cli} CONFIG SET maxmemory-policy #{before[:maxmemory_policy]}"
  else
    failures << "#{host}: Redis reads maxmemory #{after[:maxmemory]} / #{after[:maxmemory_policy]} after CONFIG SET"
  end

  # 4a. Stale volume: copy it to a new volume, then remove the original - while Elasticsearch is
  #     still running, so a failure here leaves search up. No container uses it (re-checked).
  if plan[:stale]
    out = run.call(<<~BASH, timeout: 60)
      set -euo pipefail
      if [ -n "$(sudo docker ps -a --filter volume=#{DataBoxLimits::ES_VOLUME} --format '{{.Names}}')" ]; then echo "IN_USE"; exit 0; fi
      src=$(sudo docker volume inspect #{DataBoxLimits::ES_VOLUME} --format '{{.Mountpoint}}')
      sudo docker volume create #{plan[:stale_aside]} >/dev/null
      dst=$(sudo docker volume inspect #{plan[:stale_aside]} --format '{{.Mountpoint}}')
      sudo cp -a "$src/." "$dst/"
      # Same file count on both sides before the original goes
      [ "$(sudo find "$src" | wc -l)" = "$(sudo find "$dst" | wc -l)" ] || { echo "COPY_MISMATCH"; exit 0; }
      sudo docker volume rm #{DataBoxLimits::ES_VOLUME} >/dev/null
      echo "MOVED"
    BASH
    if out.include?("MOVED")
      puts "✅ stale #{DataBoxLimits::ES_VOLUME} moved aside to #{plan[:stale_aside]}"
      rollback << "#{host} stale volume: kept as #{plan[:stale_aside]} (sudo docker volume rm #{plan[:stale_aside]} once not needed)"
    else
      # Elasticsearch has not been touched: skip the re-create
      failures << "#{host}: stale #{DataBoxLimits::ES_VOLUME} not moved (#{out.strip.lines.last}) — Elasticsearch left running as it was"
      drift = []
      reindex = false
    end
  end

  # 4. Elasticsearch: re-create through the start script, then wait for it to serve
  if drift.any?
    puts "🔧 Elasticsearch: stopping and re-creating#{' (search is down until it is healthy)' if plan[:role] == :data_box}"
    out = run.call(<<~BASH, timeout: 60)
      # The stop -> start sequence is silent for up to ~4 minutes. If the SSH session drops in that
      # time, the hang-up must not kill this script half way and leave Elasticsearch stopped:
      # ignore SIGHUP (inherited by the start script and docker) so it runs to the end on the box.
      trap '' HUP
      # Stop gracefully; a --rm container removes itself, any other is removed here
      sudo docker stop -t 60 #{DataBoxLimits::ES_CONTAINER} >/dev/null 2>&1 || true
      sudo docker rm #{DataBoxLimits::ES_CONTAINER} >/dev/null 2>&1 || true
      # --rm removal is asynchronous: wait until the name is free, or the script would try to
      # `docker start` the container being removed
      for _ in $(seq 1 30); do
        sudo docker ps -a --format '{{.Names}}' | grep -qx #{DataBoxLimits::ES_CONTAINER} || break
        sleep 1
      done
      #{DataBoxLimits::SCRIPT_PATH}
      # Healthy = cluster health answers yellow or green (yellow is normal on one node), up to 3 min
      for _ in $(seq 1 36); do
        status=$(curl -s http://localhost:9200/_cluster/health | grep -o '"status":"[a-z]*"' || true)
        case "$status" in *green*|*yellow*) echo "HEALTHY $status"; exit 0 ;; esac
        sleep 5
      done
      echo "UNHEALTHY"
      sudo docker logs --tail 20 #{DataBoxLimits::ES_CONTAINER} 2>&1 || true
    BASH
    puts out.lines.last(6).map { |l| "   #{l}" }.join
    if out.include?("HEALTHY ")
      # Prove the new shape: no drift left, and the JVM really got the heap
      es_after = DataBoxLimits.es_container_state(run.call("sudo docker inspect #{DataBoxLimits::ES_CONTAINER}"),
                                                  run.call("sudo docker image inspect #{DataBoxLimits::ES_IMAGE}"))
      jvm_after = DataBoxLimits.parse_es_jvm(run.call("curl -s http://localhost:9200/_nodes/stats/jvm"))
      left = es_after ? DataBoxLimits.es_drift(es_after, heap_mb: plan[:heap_mb], container_mb: plan[:container_mb]) : ["container not found"]
      # The JVM may report a hair under -Xmx, so allow 2%
      heap_bytes = plan[:heap_mb] * DataBoxLimits::MB
      heap_ok = jvm_after && (jvm_after[:heap_max] - heap_bytes).abs <= heap_bytes * 0.02
      if left.empty? && heap_ok
        puts "✅ Elasticsearch: heap #{plan[:heap_mb]} MB, cap #{plan[:container_mb]} MB, volume #{DataBoxLimits::ES_VOLUME}, restart unless-stopped"
      else
        failures << "#{host}: Elasticsearch came up but does not match the target: #{left.join('; ')} (heap #{jvm_after && dbl_mb(jvm_after[:heap_max])})"
      end
    else
      failures << "#{host}: Elasticsearch did not become healthy within 3 minutes — see the log lines above; the old start line is in the saved crontab"
    end
    rollback << "#{host} Elasticsearch: sudo docker rm -f #{DataBoxLimits::ES_CONTAINER}, restore the crontab, then run its old @reboot line once"
  end

  dbl_mem_line(run, "box memory now")
  # The reindex only makes sense once this box's Elasticsearch is up in its new shape
  { rollback: rollback, failures: failures, reindex: reindex && failures.none? { |f| f.include?("Elasticsearch") } }
end

namespace :ops do
  desc "Cap the data box's (and a standby replica's) Elasticsearch + Redis memory, ES volume + restart policy (dry run; EXECUTE=1 applies)"
  task :data_box_limits, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    abort "❌ Refusing #{env_name.presence || '(no env)'}: only #{DataBoxLimits::ENVS.join(', ')}. Nothing touched." unless DataBoxLimits.env_allowed?(env_name)
    execute = ENV["EXECUTE"] == "1"
    stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
    puts "\n📏 Data box limits · #{env_name} · #{execute ? 'EXECUTE' : 'dry run'}"

    # 1. Environment and account: nothing is touched if the AWS keys belong to another account
    env = dr_assess_resolve_env(env_name)
    dr_account_guard!(env)

    # 2. The data box: where the app's own Elasticsearch and Redis URLs point — must be one host
    es_host = DataBoxExporters.host_of(ENV.fetch("ELASTIC_SEARCH_URL", nil))
    redis_host = DataBoxExporters.host_of(ENV.fetch("REDIS_URL", nil))
    abort "❌ ELASTIC_SEARCH_URL / REDIS_URL missing in .env.#{env_name}. Nothing touched." if es_host.empty? || redis_host.empty?
    abort "❌ Elasticsearch (#{es_host}) and Redis (#{redis_host}) are on different hosts — this task expects one data box. Nothing touched." if es_host != redis_host

    # 2b. The MySQL replica, from the same credentials ops:mysql_buffer_pool reads
    creds = Rails.application.encrypted(Rails.root.join("config/credentials/#{env_name}.yml.enc"),
                                        key_path: Rails.root.join("config/credentials/#{env_name}.key"))
    replica = creds[:DB_HOST_REPLICA].to_s

    # 3. The route in: first app server in the stage file that answers SSH
    cap_key = dr_assess_cap_key(env[:deploy_file])
    app_ips = File.read(env[:deploy_file]).scan(Dr::DrillTeardown::SERVER_LINE).flatten.uniq
    app_host = dr_fix_live_app_host(app_ips, cap_key) or abort "❌ No app server in #{env[:deploy_file].basename} answers SSH. Nothing touched."
    abort "❌ KEYNAME is not set in .env.#{env_name}. Nothing touched." if env[:db_keyname].empty?
    ctx = { app_host: app_host, cap_key: cap_key, keyname: env[:db_keyname] }
    # One runner per box: run_on.(host).call(script)
    run_on = ->(host) { ->(script, timeout: 30) { dbx_remote(ctx, host, script, timeout: timeout) } }
    puts "🔌 via app server #{app_host}"

    # 4. Which boxes: the data box, plus the replica when it runs its own data containers
    replica_containers = replica.empty? || replica == es_host ? [] : run_on.call(replica).call("sudo docker ps --format '{{.Names}}'").split
    targets = DataBoxLimits.target_boxes(data_box: es_host, replica: replica, replica_containers: replica_containers)
    targets.reject { |t| t[:status] == :apply }.each do |t|
      puts "\n#{t[:status] == :skip ? 'ℹ️ ' : '⛔'} #{t[:host]} (replica): #{t[:reason]}"
    end

    # 5. Measure and plan every box to work on — read-only; an abort here leaves every box as it was
    plans = targets.select { |t| t[:status] == :apply }.map { |t| dbl_plan_box(run_on.call(t[:host]), t, stamp) }

    puts "\n🗺  Boxes: #{targets.map { |t| "#{t[:host]} (#{t[:role] == :replica ? 'replica' : 'data box'}) #{t[:status]}" }.join('; ')}"
    next puts "\nℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

    refused = plans.select { |p| p[:refusal] }
    abort "\n❌ #{refused.map { |p| "#{p[:host]}: #{p[:refusal]}" }.join('; ')}. Nothing touched." if refused.any?

    rollback = []
    failures = targets.select { |t| t[:status] == :refuse }.map { |t| "#{t[:host]} (replica): #{t[:reason]}" }
    reindex = false

    # 6. Apply, data box first. A failure there stops the run before the replica is touched.
    plans.each do |plan|
      result = dbl_apply_box(run_on.call(plan[:host]), plan, stamp)
      rollback.concat(result[:rollback])
      failures.concat(result[:failures])
      reindex ||= result[:reindex]
      if result[:failures].any? && plan[:role] == :data_box
        failures << "replica not touched: the data box did not apply cleanly" if plans.size > 1
        break
      end
    end

    # 7. The data box's old index lived inside the old container and is gone: queue the rebuild
    if reindex
      puts "\n🔧 Queuing the search reindex (SearchReindexJob) via cap #{env[:cap_stage]} recovery:reindex_search_later"
      out, status = Open3.capture2e("bundle exec cap #{env[:cap_stage]} recovery:reindex_search_later")
      if status.success?
        puts "✅ reindex queued — search results fill in as the job runs"
      else
        failures << "reindex not queued: run `bundle exec cap #{env[:cap_stage]} recovery:reindex_search_later` (#{out.lines.last.to_s.strip})"
      end
    end

    # 8. Outcome
    puts "\n#{'=' * 78}"
    puts "↩️  Rollback, if needed:"
    rollback.each { |r| puts "   #{r}" }
    if failures.any?
      puts "🔴 Not everything applied:"
      failures.each { |f| puts "   • #{f}" }
      abort ""
    end
    puts "🟢 Limits applied on #{env_name}. Watch the Elasticsearch and Redis dashboards for a day."
  end
end
