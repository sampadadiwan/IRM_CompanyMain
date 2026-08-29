# Post-recovery smoke test — proves a recovered (or freshly deployed) stack is
# actually SERVING, not just that the deploy/restore scripts finished.
#
# Runs ON an app server (cap recovery:verify invokes it on every app host, and
# aws:setup_infra runs that as its FINAL step, so a DR run / drill only
# succeeds if the stack verifies). Also useful standalone after any deploy:
#
#   LB=true bundle exec cap staging_in recovery:verify
#
# Contract mirrors aws:dr_readiness: prints a ✅/⚠️/❌ scorecard and exits
# non-zero on any ❌ — Capistrano's `execute :rake` then raises, failing the
# calling DR run loudly instead of reporting "deployed but dead" as success.
namespace :dr do
  desc "Smoke-test this app server + its DB box (nginx, puma, sidekiq, MySQL, Redis, ES, S3, backup arming, replication)"
  task verify: :environment do
    require "net/ssh"
    require "socket"

    results = [] # [[status, label, detail], ...] — the scorecard
    check = lambda do |label, status, detail = nil|
      results << [status, label, detail]
      icon = { ok: "✅", warn: "⚠️ ", fail: "❌" }[status]
      puts "#{icon} #{label}#{detail.to_s.empty? ? '' : " — #{detail}"}"
    end

    # Wraps a check body so one crashed check (exception) records a ❌ and the
    # REST of the scorecard still runs — mid-DR you want the full picture, not
    # a stack trace after the first broken thing.
    guarded = lambda do |label, &body|
      body.call
    rescue StandardError => e
      check.call(label, :fail, "#{e.class}: #{e.message.to_s.lines.first.to_s.strip}")
    end

    puts "🩺 dr:verify on #{Socket.gethostname} (RAILS_ENV=#{Rails.env})"

    # --- 0. prometheus_exporter FIRST, and start it if down ------------------
    # This rake process is a full Rails boot, and the app's prometheus client
    # pushes to localhost:9394 — with the exporter down it logs a connection
    # error every ~0.5s, jamming the rest of this scorecard's output. It is
    # also the second casualty of the whenever @reboot gap, so on an app box
    # (this task only ever runs on app servers) we start it rather than just
    # report it. Same command as schedule.rb's @reboot line.
    guarded.call("prometheus_exporter process") do
      count = `pgrep -fc prometheus_exporter`.strip.to_i
      if count.positive?
        check.call("prometheus_exporter process", :ok, "#{count} process(es)")
      else
        Bundler.with_unbundled_env do
          system("cd /home/ubuntu/IRM/current && RAILS_ENV=#{Rails.env} nohup bundle exec prometheus_exporter -b 0.0.0.0 " \
                 ">> /home/ubuntu/IRM/shared/log/prometheus_exporter.log 2>&1 &")
        end
        sleep 3 # give it a moment to boot and bind :9394
        count = `pgrep -fc prometheus_exporter`.strip.to_i
        check.call("prometheus_exporter process", count.positive? ? :ok : :warn,
                   count.positive? ? "was down — started it" : "not running and could not be started (see shared/log/prometheus_exporter.log)")
      end
    end

    # --- 1. Local daemons on THIS app server ---------------------------------
    guarded.call("Nginx active") do
      state = `systemctl is-active nginx`.strip
      check.call("Nginx active", state == "active" ? :ok : :fail, state)
    end

    guarded.call("Puma process") do
      # -f matches the full command line (puma masters/workers); this rake
      # process' own cmdline does not contain "puma" so it can't self-match
      count = `pgrep -fc puma`.strip.to_i
      check.call("Puma process", count.positive? ? :ok : :fail, "#{count} process(es)")
    end

    # --- 2. HTTP through the full serving chain ------------------------------
    # Curling localhost with the real Host header exercises nginx → puma →
    # Rails → dependency — exactly the path the ALB uses. Plain HTTP on
    # purpose: TLS terminates at the ALB, nginx listens on :80 only, and the
    # nginx template hardcodes X-Forwarded-Proto https so force_ssl does not
    # redirect (https://localhost would be connection-refused → HTTP 000).
    # Retries: puma:restart fires seconds before this task (same
    # nginx:switch_app hook), so give a rebooting puma up to 30s per endpoint.
    # The Host header must address the APP host — never the apex.
    #
    # On production the apex (caphive.com) is the marketing website: nginx
    # serves it straight from public/website and the Website middleware backs
    # that up, so every /health_check/* URL there is a legitimate 404. Verified
    # on a production DR box: caphive.com -> 404, www.caphive.com -> 301,
    # app.caphive.com -> 200.
    #
    # DOMAIN cannot be used as-is because it means different things per
    # environment — production sets the apex, staging sets the app host
    # (dev.altconnects.com). So reduce it to the base domain and rebuild the
    # app host, which is correct for both without inspecting WEBSITE_HOSTS:
    #   caphive.com         -> caphive.com     -> app.caphive.com
    #   dev.altconnects.com -> altconnects.com -> dev.altconnects.com
    #
    # Same convention as aws:dns_cutover and aws:dr_verify_edge. Base domain is
    # the last two labels — every domain here is a .com; a multi-part public
    # suffix (foo.co.uk) would need a real public-suffix list.
    domain = ENV["DOMAIN"].to_s.sub(%r{\Ahttps?://}, "").split("/").first.to_s
    raise "DOMAIN is not set — cannot derive the health-check host" if domain.empty?

    base_domain = domain.split(".").last(2).join(".")
    host_header = "#{Rails.env.production? ? 'app' : 'dev'}.#{base_domain}"
    puts "🌐 Health checks will use Host: #{host_header}"
    http = lambda do |path, attempts: 6|
      code = nil
      attempts.times do |i|
        code = `curl -s -o /dev/null -w "%{http_code}" --max-time 60 -H "Host: #{host_header}" http://localhost#{path}`.strip
        break if code == "200"

        sleep 5 if i < attempts - 1
      end
      code
    end

    { "/health_check/db_check"      => "HTTP db_check (nginx→puma→MySQL)",
      "/health_check/redis_check"   => "HTTP redis_check (nginx→puma→Redis cache)",
      "/health_check/elastic_check" => "HTTP elastic_check (nginx→puma→Elasticsearch)",
      "/health_check/disk_check"    => "HTTP disk_check (root filesystem <95%)" }.each do |path, label|
      guarded.call(label) do
        code = http.call("#{path}.json")
        check.call(label, code == "200" ? :ok : :fail, "HTTP #{code}")
      end
    end

    # XIRR runs as a docker container started by whenever's @reboot crontab —
    # which cap installs AFTER first boot, so on a FRESH box it is down until
    # started by hand or the next reboot (fund IRR calcs fail until then)
    guarded.call("HTTP xirr_check (xirr_py docker)") do
      code = http.call("/health_check/xirr_check.json")
      check.call("HTTP xirr_check (xirr_py docker)", code == "200" ? :ok : :fail,
                 code == "200" ? "HTTP 200" : "HTTP #{code} — fresh box? start it: sudo docker run -d --rm --name xirr_py -p 8000:80 -v /tmp:/tmp thimmaiah/xirr_py:v2.6")
    end


    # --- 3. Rails-level checks (this process IS the app: real env + creds) ---
    guarded.call("Sidekiq workers registered") do
      # ProcessSet lives in Redis: proves sidekiq booted AND registered itself,
      # which pgrep alone can't (a wedged sidekiq still has a process).
      # sidekiq:restart fires seconds before this task (same nginx:switch_app
      # hook) and registration takes a few seconds — poll up to 60s.
      size = 0
      13.times do |i|
        size = Sidekiq::ProcessSet.new.size
        break if size.positive?

        sleep 5 if i < 12
      end
      check.call("Sidekiq workers registered", size.positive? ? :ok : :fail,
                 size.positive? ? "#{size} process(es)" : "0 registered after waiting 60s")
    end

    guarded.call("Migrations current") do
      ActiveRecord::Migration.check_all_pending! # raises if any pending
      check.call("Migrations current", :ok)
    rescue ActiveRecord::PendingMigrationError
      check.call("Migrations current", :fail, "pending migrations — run: cap <stage> recovery:migrate")
    end

    guarded.call("Restored data freshness") do
      # A restore from a STALE backup passes every other check — catch it via
      # newest row timestamps. Incrementals run hourly, fulls daily, so a
      # healthy restore should be well under 72h behind.
      newest = [User, Document].filter_map { |m| m.unscoped.maximum(:updated_at) }.max
      raise "no rows in users/documents — empty restore?" if newest.nil?

      age_h = ((Time.current - newest) / 3600).round(1)
      check.call("Restored data freshness", age_h > 72 ? :warn : :ok,
                 "newest users/documents row is #{age_h}h old#{' — restored from a STALE backup?' if age_h > 72}")
    end

    guarded.call("S3 app bucket reachable") do
      # head_bucket with the app's own env/credentials — proves uploads will work
      bucket = ENV.fetch("AWS_S3_BUCKET")
      Aws::S3::Client.new(region: ENV.fetch("AWS_REGION")).head_bucket(bucket: bucket)
      check.call("S3 app bucket reachable", :ok, bucket)
    end

    # --- 4. DB box checks (SSH — DB boxes accept SSH only from app servers,
    #         which is exactly why this task runs here and not on a laptop) ---
    db_host = Rails.application.credentials[:DB_HOST]
    replica_host = Rails.application.credentials[:DB_HOST_REPLICA]
    key_path = File.expand_path("~/.ssh/#{ENV.fetch('KEYNAME')}.pem")

    on_db_box = lambda do |host, cmd|
      # verify_host_key: :never — see the matching comment in backup_db.rake's
      # run_baked_restore; DB boxes get recreated with fresh host keys but
      # often reuse the same private IP.
      Net::SSH.start(host, "ubuntu", keys: [key_path], timeout: 15, verify_host_key: :never) { |ssh| ssh.exec!(cmd).to_s.strip }
    end

    guarded.call("Primary DB box (#{db_host})") do
      state = on_db_box.call(db_host, "systemctl is-active mysql")
      check.call("Primary mysqld (#{db_host})", state == "active" ? :ok : :fail, state)

      # ES + Redis run as docker containers started by the ubuntu user's
      # @reboot crontab (baked into the DB AMI). ubuntu is in the docker group
      # on baked AMIs; the sudo fallback covers older, pre-bake boxes.
      names = on_db_box.call(db_host, "docker ps --format '{{.Names}}' 2>/dev/null || sudo docker ps --format '{{.Names}}'")
      %w[elasticsearch redis-stack-server].each do |container|
        check.call("Primary docker: #{container}", names.include?(container) ? :ok : :fail,
                   names.include?(container) ? "running" : "not in docker ps — run /usr/local/bin/start_data_containers.sh on the box (pre-2026-07-10 AMIs: raw @reboot raced the docker daemon)")
      end

      # Backups must be ARMED on the primary — restore_primary creates the
      # marker; without it /etc/cron.d/irm-db-backup no-ops forever and the
      # freshly recovered env silently takes NO backups
      armed = on_db_box.call(db_host, "test -f /etc/db_backup_enabled && echo yes")
      check.call("Primary backup cron armed", armed == "yes" ? :ok : :fail,
                 armed == "yes" ? "/etc/db_backup_enabled present" : "marker missing — no backups will be taken!")

      cron = on_db_box.call(db_host, "test -f /etc/cron.d/irm-db-backup && echo yes")
      check.call("Primary backup cron installed", cron == "yes" ? :ok : :warn,
                 cron == "yes" ? nil : "no /etc/cron.d/irm-db-backup — pre-bake AMI?")
    end

    # --- 5. Replica + replication (only on stacks that HAVE a replica) -------
    if replica_host.to_s.empty? || replica_host == db_host
      check.call("Replication", :ok, "skipped — no separate replica configured for this stack")
    else
      guarded.call("Replica DB box (#{replica_host})") do
        state = on_db_box.call(replica_host, "systemctl is-active mysql")
        check.call("Replica mysqld (#{replica_host})", state == "active" ? :ok : :fail, state)

        # Single writer per backup chain: the replica must be DISARMED
        # (restore_replica_remote removes the marker restore_primary created)
        armed = on_db_box.call(replica_host, "test -f /etc/db_backup_enabled && echo yes")
        check.call("Replica backup cron disarmed", armed == "yes" ? :fail : :ok,
                   armed == "yes" ? "ARMED — two writers will corrupt the backup chain!" : nil)
      end

      guarded.call("Replication live round-trip") do
        # Strongest possible replication check: write a timestamp through the
        # primary connection, read it back on the :reading role (the replica)
        # a few seconds later — same mechanism the hourly health job uses
        job = ReplicationHealthJob.new
        if job.user.nil?
          check.call("Replication live round-trip", :warn,
                     "no support-role user in restored data — check SHOW REPLICA STATUS manually")
        else
          job.perform
          status = job.replication_health_status
          check.call("Replication live round-trip", status == "Ok" ? :ok : :fail, status.to_s)
        end
      end
    end

    # --- Scorecard ------------------------------------------------------------
    fails = results.count { |s, _, _| s == :fail }
    warns = results.count { |s, _, _| s == :warn }
    puts "\n#{fails.zero? ? '🟢' : '🔴'} dr:verify — #{results.size} checks: " \
         "#{results.size - fails - warns} ok, #{warns} warnings, #{fails} failures"
    abort "❌ dr:verify FAILED on #{Socket.gethostname} — stack is NOT healthy (see above)" if fails.positive?
  end
end
