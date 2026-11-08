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
    # On production the apex (caphive.com) is the website: nginx serves it
    # straight from public/website and the Website middleware backs that up, so
    # every /health_check/* URL there is a legitimate 404. Verified on a
    # production DR box: caphive.com -> 404, www.caphive.com -> 301,
    # app.caphive.com -> 200.
    #
    # HOST *is* the app host and every .env file sets it — app.caphive.com,
    # app.caphive.us, dev.altconnects.com, dev.altconnects.us — so read it
    # rather than re-deriving a value we already have.
    host_header = ENV["HOST"].to_s.sub(%r{\Ahttps?://}, "").split("/").first.to_s.strip
    if host_header.empty?
      # Fallback for a stack whose env file predates HOST. DOMAIN can't be used
      # as-is because it means different things per environment — production
      # sets the apex, staging sets the app host — so reduce it to the base
      # domain and re-prefix, matching aws:dns_cutover and aws:dr_verify_edge:
      #   caphive.com         -> caphive.com     -> app.caphive.com
      #   dev.altconnects.com -> altconnects.com -> dev.altconnects.com
      # Note the two guesses this makes and HOST doesn't: the app prefix comes
      # from RAILS_ENV, and the base domain is assumed to be the last two labels
      # (fine for .com/.us; a multi-part suffix like foo.co.uk would need a real
      # public-suffix list). That is why it is the fallback, not the primary.
      domain = ENV["DOMAIN"].to_s.sub(%r{\Ahttps?://}, "").split("/").first.to_s.sub(/\Awww\./, "")
      raise "Neither HOST nor DOMAIN is set — cannot derive the health-check host" if domain.empty?

      base_domain = domain.split(".").last(2).join(".")
      host_header = "#{Rails.env.production? ? 'app' : 'dev'}.#{base_domain}"
      puts "⚠️  HOST not set — derived the health-check host from DOMAIN instead"
    end
    puts "🌐 Health checks will use Host: #{host_header}"
    # host:/expect: default to the app host and 200 so existing callers are
    # unchanged; the website checks below need a different host, and the
    # www alias legitimately answers 301 rather than 200.
    http = lambda do |path, host: host_header, expect: "200", attempts: 6|
      code = nil
      attempts.times do |i|
        code = `curl -s -o /dev/null -w "%{http_code}" --max-time 60 -H "Host: #{host}" http://localhost#{path}`.strip
        break if code == expect

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

    # --- 2b. Static marketing website on the apex ----------------------------
    # The apex is a SEPARATE serving path from the app: nginx serves it straight
    # from public/website (the Website middleware is the fallback). Every check
    # above uses the app host, so a recovery that brought the application back
    # but lost the public website would pass silently — half a recovery
    # reported as a whole one.
    # Gated on WEBSITE_HOSTS, the same opt-in the middleware itself uses; the
    # first entry is canonical and the rest 301 to it (see lib/middleware/website.rb).
    website_hosts = ENV["WEBSITE_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?)
    if website_hosts.empty?
      # :warn, not :ok — a check that did not run must never be counted among
      # the ones that passed. The scorecard feeds an auditor-facing report whose
      # headline is "N of M checks passed"; a skip rendered as ✅ inflates it.
      # (.env.staging.us has no WEBSITE_HOSTS today, so this path is live.)
      check.call("Static website", :warn, "skipped — WEBSITE_HOSTS not set for this stack")
    else
      canonical, *alias_hosts = website_hosts
      guarded.call("HTTP website apex (#{canonical})") do
        code = http.call("/", host: canonical)
        check.call("HTTP website apex (#{canonical})", code == "200" ? :ok : :fail,
                   code == "200" ? "serving public/website" : "HTTP #{code} — apex not serving the website")
      end
      alias_hosts.each do |alias_host|
        label = "HTTP website alias (#{alias_host})"
        guarded.call(label) do
          # A redirect to the canonical host is the CORRECT answer here, so
          # don't retry-until-200 — that would burn 30s and then report a false
          # failure on a perfectly healthy alias.
          code = http.call("/", host: alias_host, expect: "301", attempts: 2)
          check.call(label, %w[301 308].include?(code) ? :ok : :fail,
                     %w[301 308].include?(code) ? "redirects to #{canonical}" : "HTTP #{code} — expected 301 to #{canonical}")
        end
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

    guarded.call("Search index populated") do
      # elastic_check above only proves Elasticsearch ANSWERS — an empty index
      # passes it. Search is not backed up, so prove every index the DR rebuilt
      # holds its MySQL scope's records (within a small tolerance: traffic is
      # back on, so a few writes may be in flight).
      grades = Dr::SearchIndexes.indexes.map do |index|
        Dr::SearchIndexes.grade(index_name: index.name, es: Dr::SearchIndexes.es_count(index),
                                db: Dr::SearchIndexes.db_count(index), exact: false,
                                maintained: Dr::SearchIndexes.maintained?(index))
      end
      # Worst verdict wins: any maintained index short → fail; only unmaintained drift → warn
      failed = grades.select { |grade| grade.status == :fail }
      warned = grades.select { |grade| grade.status == :warn }
      status = if failed.any?
                 :fail
               elsif warned.any?
                 :warn
               else
                 :ok
               end
      detail = if status == :ok then "#{grades.size}/#{grades.size} indexes hold their records"
               else (failed + warned).map(&:detail).join("; ")
               end
      check.call("Search index populated", status, detail)
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

    # Old backup jobs in the box's ubuntu + root crontabs. DR boxes are cloned
    # from a snapshot of the live box, whose ubuntu crontab still runs
    # /home/ubuntu/backup_db.sh — a writer that ignores the armed marker. The
    # restore strips them; this proves it did (Dr::BackupSchedule).
    old_backup_jobs = lambda do |host|
      # 2>&1: "no crontab for <user>" goes to stderr, and split_crontab drops it
      Dr::BackupSchedule.old_jobs(on_db_box.call(host, "crontab -l 2>&1; sudo crontab -l -u root 2>&1"))
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
      armed = on_db_box.call(db_host, "test -f #{Dr::BackupSchedule::ARMED_MARKER} && echo yes")
      # A DR drill must be the opposite: NOT armed, because the live box is
      # still writing the same bucket (DR_DRILL=true, set by aws:dr_drill)
      drill = Dr::BackupSchedule.drill?
      grade = Dr::BackupSchedule.grade_armed(armed == "yes", drill: drill)
      check.call(drill ? "Primary backup cron NOT armed (drill)" : "Primary backup cron armed", grade.status, grade.detail)

      # Something must actually RUN the script, and only one thing may: the
      # baked schedule with no old job beside it. A missing schedule used to be
      # a warning, so two drills passed with backups off (fix-dr-backup-cron-after-restore).
      schedule = on_db_box.call(db_host, "test -f #{Dr::BackupSchedule::CRON_PATH} && echo yes") == "yes"
      grade = Dr::BackupSchedule.grade_primary(schedule: schedule, old_jobs: old_backup_jobs.call(db_host))
      check.call("Primary backup schedule (single writer)", grade.status, grade.detail)
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

        # Disarmed is not enough: an old cloned crontab job ignores the marker
        grade = Dr::BackupSchedule.grade_replica(old_jobs: old_backup_jobs.call(replica_host))
        check.call("Replica has no backup writer", grade.status, grade.detail)
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
