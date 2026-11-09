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
# What EXECUTE does, in order:
#   1. installs the repo's start_data_containers.sh and /etc/default/irm-data-containers (limits)
#   2. swaps the old raw `@reboot docker run` crontab lines for the script's line (crontab saved)
#   3. Redis: CONFIG SET maxmemory + noeviction — live, NO restart (a restart would lose Sidekiq's
#      queues: Redis has no volume)
#   4. Elasticsearch: only if it differs from the target — stop, re-create through the script
#      (memory cap, heap, elasticsearch-data volume, --restart unless-stopped), wait for health
#   5. queues the search reindex when the old index lived inside the container (it is gone)
#
# Elasticsearch is DOWN for ~1-2 minutes in step 4 and search results are incomplete until the
# reindex job finishes — on production, run it in a quiet window. Refuses (before touching
# anything) when the live container runs another image or carries settings the script lacks.
#
# Reaches the data box through an app server, like observability:data_box_exporters (dbx_remote).

require "base64"
require "digest"
require "json"
require "open3"

namespace :ops do
  desc "Cap the data box's Elasticsearch + Redis memory, ES volume + restart policy (dry run; EXECUTE=1 applies)"
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
    host = es_host

    # 3. The route in: first app server in the stage file that answers SSH
    cap_key = dr_assess_cap_key(env[:deploy_file])
    app_ips = File.read(env[:deploy_file]).scan(Dr::DrillTeardown::SERVER_LINE).flatten.uniq
    app_host = dr_fix_live_app_host(app_ips, cap_key) or abort "❌ No app server in #{env[:deploy_file].basename} answers SSH. Nothing touched."
    abort "❌ KEYNAME is not set in .env.#{env_name}. Nothing touched." if env[:db_keyname].empty?
    ctx = { app_host: app_host, cap_key: cap_key, keyname: env[:db_keyname] }
    sh = ->(script, timeout: 30) { dbx_remote(ctx, host, script, timeout: timeout) }
    puts "🔌 #{host} via app server #{app_host}"

    # 4. Measure (read-only, every run)
    mem_line = ->(label) { puts "   #{label}: #{sh.call("free -m | awk '/^Mem:/ {printf \"%d MB available of %d MB\", $7, $2}'")}" }
    mem_line.call("box memory")
    redis = DataBoxLimits.parse_redis_info(sh.call("sudo docker exec #{DataBoxLimits::REDIS_CONTAINER} redis-cli INFO memory"))
    abort "❌ Could not read Redis INFO from #{DataBoxLimits::REDIS_CONTAINER} on #{host}. Nothing touched." if redis[:used_memory_peak].zero?

    jvm = DataBoxLimits.parse_es_jvm(sh.call("curl -s http://localhost:9200/_nodes/stats/jvm"))
    abort "❌ Elasticsearch on #{host}:9200 did not return JVM stats. Nothing touched." unless jvm

    container_json = sh.call("sudo docker inspect #{DataBoxLimits::ES_CONTAINER}")
    image = begin
      Array(JSON.parse(container_json)).first&.dig("Config", "Image").to_s
    rescue JSON::ParserError
      ""
    end
    es = DataBoxLimits.es_container_state(container_json, sh.call("sudo docker image inspect #{image}"))
    abort "❌ No #{DataBoxLimits::ES_CONTAINER} container on #{host}. Nothing touched." unless es

    mb = ->(bytes) { "#{(bytes / DataBoxLimits::MB.to_f).round(1)} MB" }
    puts "\n📋 Measured"
    puts "   Elasticsearch: heap #{mb.call(jvm[:heap_max])}, live data (old gen) now #{mb.call(jvm[:old_used])}, " \
         "peak #{mb.call(jvm[:old_peak])} over #{(jvm[:uptime_s] / 86_400.0).round(1)} days"
    puts "   Elasticsearch container: #{es[:image]}, memory cap #{es[:memory_mb].zero? ? 'none' : "#{es[:memory_mb]} MB"}, " \
         "#{es[:auto_remove] ? '--rm' : "restart=#{es[:restart].presence || 'no'}"}, data #{es[:volume] ? "in volume #{es[:volume]}" : 'inside the container'}"
    puts "   Redis: used #{mb.call(redis[:used_memory])}, peak #{mb.call(redis[:used_memory_peak])}, " \
         "maxmemory #{redis[:maxmemory].zero? ? 'unlimited' : mb.call(redis[:maxmemory])} (#{redis[:maxmemory_policy]})"

    # 5. Size from the measurements: max(3 x peak, 512 MB)
    heap_mb = DataBoxLimits.es_heap_mb(jvm[:old_peak])
    container_mb = DataBoxLimits.es_container_mb(heap_mb)
    redis_max = DataBoxLimits.redis_maxmemory_bytes(redis[:used_memory_peak])
    puts "\n📐 Limits = max(3 x peak, 512 MB)"
    puts "   Elasticsearch heap: max(3 x #{mb.call(jvm[:old_peak])}, 512 MB) -> #{heap_mb} MB; container cap max(2 x heap, heap + 1 GB) -> #{container_mb} MB"
    puts "   Redis maxmemory:    max(3 x #{mb.call(redis[:used_memory_peak])}, 512 MB) -> #{redis_max / DataBoxLimits::MB} MB, noeviction"

    # 6. The plan
    drift = DataBoxLimits.es_drift(es, heap_mb: heap_mb, container_mb: container_mb)
    refusal = DataBoxLimits.es_recreate_refusal(es)
    crontab_before = sh.call("crontab -l 2>&1")
    cron = DataBoxLimits.crontab_plan(crontab_before)
    defaults = DataBoxLimits.defaults_file(heap_mb: heap_mb, container_mb: container_mb, redis_maxmemory_bytes: redis_max)
    script = Rails.root.join(DataBoxLimits::SCRIPT_REPO_PATH).read
    script_current = sh.call("sha256sum #{DataBoxLimits::SCRIPT_PATH} 2>/dev/null | cut -d' ' -f1") == Digest::SHA256.hexdigest(script)
    reindex = drift.any? && es[:volume] != DataBoxLimits::ES_VOLUME
    # A volume of that name the live container does not use holds an earlier container's index
    volume_exists = sh.call("sudo docker volume inspect #{DataBoxLimits::ES_VOLUME} >/dev/null 2>&1 && echo EXISTS").include?("EXISTS")
    stale = drift.any? && DataBoxLimits.stale_volume?(es, volume_exists: volume_exists)
    stale_aside = "#{DataBoxLimits::ES_VOLUME}-stale-#{stamp}"
    stale_detail = stale ? sh.call(<<~BASH).strip : ""
      mp=$(sudo docker volume inspect #{DataBoxLimits::ES_VOLUME} --format '{{.Mountpoint}}')
      users=$(sudo docker ps -a --filter volume=#{DataBoxLimits::ES_VOLUME} --format '{{.Names}}' | tr '\n' ' ')
      echo "$(sudo du -sh "$mp" | cut -f1), last written $(sudo find "$mp" -type f -printf '%TY-%Tm-%Td\n' | sort | tail -1), used by: ${users:-no container}"
    BASH

    puts "\n🗺  Plan"
    puts "   • #{script_current ? 'start script already current' : "install #{DataBoxLimits::SCRIPT_PATH} from the repo"}; write #{DataBoxLimits::DEFAULTS_PATH}"
    puts "   • crontab: #{cron[:status] == :unchanged ? 'already uses the start script' : "replace #{cron[:removed].size} raw @reboot line(s) with the start script"}"
    cron[:removed].each { |l| puts "       - #{l}" }
    puts "   • Redis: CONFIG SET maxmemory #{redis_max} (#{redis_max / DataBoxLimits::MB} MB) + noeviction — live, no restart"
    if drift.empty?
      puts "   • Elasticsearch: already at the target — not touched"
    else
      puts "   • Elasticsearch: re-create (DOWN ~1-2 min#{'; index rebuilt by the reindex job' if reindex})"
      drift.each { |d| puts "       - #{d}" }
    end
    if stale
      puts "   • Elasticsearch: an unused #{DataBoxLimits::ES_VOLUME} volume already exists (#{stale_detail}) — " \
           "moved aside to #{stale_aside} BEFORE Elasticsearch stops, so the new container starts empty"
    end
    puts "   ⛔ Elasticsearch cannot be re-created: #{refusal}" if drift.any? && refusal
    next puts "\nℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

    abort "\n❌ #{refusal}. Nothing touched." if drift.any? && refusal

    rollback = []
    failures = []

    # 7. Start script + limits file. The old limits file (if any) is kept beside the new one.
    out = sh.call(<<~BASH)
      set -euo pipefail
      echo #{Base64.strict_encode64(script)} | base64 -d > /tmp/start_data_containers.sh
      sudo install -m 0755 -o root -g root /tmp/start_data_containers.sh #{DataBoxLimits::SCRIPT_PATH}
      rm -f /tmp/start_data_containers.sh
      if [ -f #{DataBoxLimits::DEFAULTS_PATH} ]; then sudo cp -p #{DataBoxLimits::DEFAULTS_PATH} #{DataBoxLimits::DEFAULTS_PATH}.bak-#{stamp}; fi
      echo #{Base64.strict_encode64(defaults)} | base64 -d | sudo tee #{DataBoxLimits::DEFAULTS_PATH} >/dev/null
      sudo chmod 0644 #{DataBoxLimits::DEFAULTS_PATH}
      echo INSTALLED
    BASH
    abort "❌ Installing the start script / limits file failed:\n#{out}" unless out.include?("INSTALLED")
    puts "\n✅ start script and #{DataBoxLimits::DEFAULTS_PATH} installed"

    # 8. Crontab: save, write, re-read to prove it
    if cron[:status] == :changed
      saved = "~/crontab.before-data-box-limits.#{stamp}"
      written = sh.call("crontab -l > #{saved} 2>/dev/null; echo #{Base64.strict_encode64(cron[:text])} | base64 -d | crontab - && echo OK")
      verdict = DataBoxLimits.crontab_plan(sh.call("crontab -l 2>&1"))
      if written.include?("OK") && verdict[:status] == :unchanged
        puts "✅ crontab: boots through the start script (old crontab saved to #{saved})"
        rollback << "crontab: crontab #{saved}"
      else
        failures << "crontab not updated (#{written.strip}) — saved copy #{saved}"
      end
    end

    # 9. Redis: live limit, no restart — then read it back
    redis_cli = "sudo docker exec #{DataBoxLimits::REDIS_CONTAINER} redis-cli"
    sh.call("#{redis_cli} CONFIG SET maxmemory #{redis_max} && #{redis_cli} CONFIG SET maxmemory-policy noeviction")
    after = DataBoxLimits.parse_redis_info(sh.call("#{redis_cli} INFO memory"))
    if after[:maxmemory] == redis_max && after[:maxmemory_policy] == "noeviction"
      puts "✅ Redis: maxmemory #{redis_max / DataBoxLimits::MB} MB, noeviction (used #{mb.call(after[:used_memory])})"
      rollback << "Redis: #{redis_cli} CONFIG SET maxmemory #{redis[:maxmemory]} && #{redis_cli} CONFIG SET maxmemory-policy #{redis[:maxmemory_policy]}"
    else
      failures << "Redis reads maxmemory #{after[:maxmemory]} / #{after[:maxmemory_policy]} after CONFIG SET"
    end

    # 10a. Stale volume: copy it to a new volume, then remove the original - while Elasticsearch is
    #      still running, so a failure here leaves search up. No container uses it (re-checked).
    if stale
      out = sh.call(<<~BASH, timeout: 60)
        set -euo pipefail
        if [ -n "$(sudo docker ps -a --filter volume=#{DataBoxLimits::ES_VOLUME} --format '{{.Names}}')" ]; then echo "IN_USE"; exit 0; fi
        src=$(sudo docker volume inspect #{DataBoxLimits::ES_VOLUME} --format '{{.Mountpoint}}')
        sudo docker volume create #{stale_aside} >/dev/null
        dst=$(sudo docker volume inspect #{stale_aside} --format '{{.Mountpoint}}')
        sudo cp -a "$src/." "$dst/"
        # Same file count on both sides before the original goes
        [ "$(sudo find "$src" | wc -l)" = "$(sudo find "$dst" | wc -l)" ] || { echo "COPY_MISMATCH"; exit 0; }
        sudo docker volume rm #{DataBoxLimits::ES_VOLUME} >/dev/null
        echo "MOVED"
      BASH
      if out.include?("MOVED")
        puts "✅ stale #{DataBoxLimits::ES_VOLUME} moved aside to #{stale_aside}"
        rollback << "stale volume: kept as #{stale_aside} (sudo docker volume rm #{stale_aside} once not needed)"
      else
        # Elasticsearch has not been touched: abort before the re-create
        failures << "stale #{DataBoxLimits::ES_VOLUME} not moved (#{out.strip.lines.last}) — Elasticsearch left running as it was"
        drift = []
        reindex = false
      end
    end

    # 10. Elasticsearch: re-create through the start script, then wait for it to serve
    if drift.any?
      puts "\n🔧 Elasticsearch: stopping and re-creating (search is down until it is healthy)"
      out = sh.call(<<~BASH, timeout: 60)
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
        es_after = DataBoxLimits.es_container_state(sh.call("sudo docker inspect #{DataBoxLimits::ES_CONTAINER}"),
                                                    sh.call("sudo docker image inspect #{DataBoxLimits::ES_IMAGE}"))
        jvm_after = DataBoxLimits.parse_es_jvm(sh.call("curl -s http://localhost:9200/_nodes/stats/jvm"))
        left = es_after ? DataBoxLimits.es_drift(es_after, heap_mb: heap_mb, container_mb: container_mb) : ["container not found"]
        # The JVM may report a hair under -Xmx, so allow 2%
        heap_ok = jvm_after && (jvm_after[:heap_max] - (heap_mb * DataBoxLimits::MB)).abs <= heap_mb * DataBoxLimits::MB * 0.02
        if left.empty? && heap_ok
          puts "✅ Elasticsearch: heap #{heap_mb} MB, cap #{container_mb} MB, volume #{DataBoxLimits::ES_VOLUME}, restart unless-stopped"
        else
          failures << "Elasticsearch came up but does not match the target: #{left.join('; ')} (heap #{jvm_after && mb.call(jvm_after[:heap_max])})"
        end
      else
        failures << "Elasticsearch did not become healthy within 3 minutes — see the log lines above; the old start line is in the saved crontab"
      end
    end

    # 11. The old index lived inside the old container and is gone: queue the rebuild
    if reindex && failures.none? { |f| f.start_with?("Elasticsearch") }
      puts "\n🔧 Queuing the search reindex (SearchReindexJob) via cap #{env[:cap_stage]} recovery:reindex_search_later"
      out, status = Open3.capture2e("bundle exec cap #{env[:cap_stage]} recovery:reindex_search_later")
      if status.success?
        puts "✅ reindex queued — search results fill in as the job runs"
      else
        failures << "reindex not queued: run `bundle exec cap #{env[:cap_stage]} recovery:reindex_search_later` (#{out.lines.last.to_s.strip})"
      end
    end

    # 12. Outcome
    mem_line.call("box memory now")
    puts "\n#{'=' * 78}"
    puts "↩️  Rollback, if needed (on #{host}):"
    rollback.each { |r| puts "   #{r}" }
    puts "   Elasticsearch: sudo docker rm -f #{DataBoxLimits::ES_CONTAINER}, restore the crontab, then run its old @reboot line once" if drift.any?
    if failures.any?
      puts "🔴 Not everything applied:"
      failures.each { |f| puts "   • #{f}" }
      abort ""
    end
    puts "🟢 Limits applied on #{env_name}. Watch the Elasticsearch and Redis dashboards for a day."
  end
end
