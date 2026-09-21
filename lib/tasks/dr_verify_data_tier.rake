#  dr:verify_data_tier — prove Redis, Sidekiq and Elasticsearch actually work
# =============================================================================
# Phase 4 of component recovery (see docs/operations/dr/dr_component_recovery.md).
#
# Runs ON an app server (via `cap <stage> partial:verify_data_tier`), because it
# uses the application's own REDIS_URL / ELASTIC_SEARCH_URL and credentials.
#
# WHY THIS EXISTS: dr:verify's "redis_check" does NOT check Redis. It curls
# /health_check/redis_check, which exercises Rails.cache — and this app uses
# :solid_cache_store, i.e. MySQL. So after any repair that moves Redis to a new
# address, every existing check can pass while Sidekiq and ActionCable point at
# a dead Redis. Recorded as finding #5 in dr_component_recovery.md.
#
# Deliberately additive: dr:verify is drill-tested and is not modified.
#
#   bundle exec cap production_in partial:verify_data_tier
#   RAILS_ENV=production bundle exec rake dr:verify_data_tier   # on the box
#
# Exits non-zero on any ❌ so a calling cap task fails loudly.
# =============================================================================

namespace :dr do
  desc "Verify Redis, Sidekiq and Elasticsearch from inside the app (run on an app server)"
  task verify_data_tier: :environment do
    require "socket"

    results = []
    check = lambda do |label, status, detail = nil|
      results << [status, label, detail]
      icon = { ok: "✅", warn: "⚠️ ", fail: "❌" }[status]
      puts "#{icon} #{label}#{detail.to_s.empty? ? '' : " — #{detail}"}"
    end

    # One broken check must not cost the rest of the scorecard.
    guarded = lambda do |label, &body|
      body.call
    rescue StandardError => e
      check.call(label, :fail, "#{e.class}: #{e.message.to_s.lines.first.to_s.strip}")
    end

    puts "🩺 dr:verify_data_tier on #{Socket.gethostname} (RAILS_ENV=#{Rails.env})"

    # --- Redis: the real thing, not the cache -----------------------------
    redis_url = ENV.fetch("REDIS_URL", nil)
    guarded.call("Redis reachable") do
      if redis_url.to_s.empty?
        check.call("Redis reachable", :fail, "REDIS_URL is not set in this environment")
      else
        # Short timeouts on purpose: a dead Redis should fail this check in
        # seconds, not hang a post-repair verification.
        redis = Redis.new(url: redis_url, timeout: 5, reconnect_attempts: 0)
        pong = redis.ping
        # Round-trip a value too — PING can succeed against a Redis that is
        # loading a dump and rejecting real commands.
        stamp = Time.current.to_f.to_s
        redis.setex("dr:verify_data_tier", 60, stamp)
        echoed = redis.get("dr:verify_data_tier")
        check.call("Redis reachable", pong == "PONG" && echoed == stamp ? :ok : :fail,
                   "#{redis_url.sub(%r{//.*@}, '//')} — PING=#{pong}, round-trip #{echoed == stamp ? 'ok' : 'MISMATCH'}")
      end
    end

    # --- Sidekiq: registered workers, not just a running process ----------
    guarded.call("Sidekiq workers registered") do
      require "sidekiq/api"
      # ProcessSet lives in Redis, so this also proves Sidekiq is talking to the
      # SAME Redis this app is configured for — a pgrep cannot.
      size = Sidekiq::ProcessSet.new.size
      check.call("Sidekiq workers registered", size.positive? ? :ok : :fail,
                 size.positive? ? "#{size} process(es)" : "0 registered — sidekiq is down or on a different Redis")
    end

    guarded.call("Sidekiq queue backlog") do
      require "sidekiq/api"
      queues = Sidekiq::Queue.all
      total = queues.sum(&:size)
      worst = queues.max_by(&:latency)
      # After a Redis replacement the queues are EMPTY because their contents
      # died with the old box — that is expected, and is why this is never a
      # failure. A large backlog with high latency means workers are not
      # draining, which is worth seeing right after a repair.
      status = worst && worst.latency > 900 ? :warn : :ok
      check.call("Sidekiq queue backlog", status,
                 "#{total} job(s) across #{queues.size} queue(s)" \
                 "#{worst ? ", oldest #{worst.name} #{worst.latency.round}s" : ''}")
    end

    # --- Elasticsearch: the index the app actually searches ---------------
    guarded.call("Elasticsearch index") do
      # FolderIndex backs Folder.search, which is what /health_check/elastic_check
      # exercises. An index that is absent (rather than merely empty) means the
      # ES box was replaced and nothing has reindexed yet.
      if FolderIndex.exists?
        count = begin
          FolderIndex.total
        rescue StandardError
          nil
        end
        check.call("Elasticsearch index", count.to_i.positive? ? :ok : :warn,
                   count.nil? ? "index exists" : "index exists, #{count} document(s)" \
                   "#{count.to_i.zero? ? ' — empty, run rake chewy:reset' : ''}")
      else
        check.call("Elasticsearch index", :fail,
                   "FolderIndex does not exist — rebuild it with: RAILS_ENV=#{Rails.env} rake chewy:reset")
      end
    end

    # --- ActionCable shares the Redis above -------------------------------
    # Reported rather than probed: cable.yml resolves REDIS_URL at boot, so if
    # the check above passed against a DIFFERENT url than the running puma has,
    # the mismatch is the thing worth surfacing.
    guarded.call("ActionCable adapter") do
      cable = Rails.application.config_for(:cable)
      configured = (cable[:url] || cable["url"]).to_s
      # Both values must be present before comparing: "".start_with?("") is
      # TRUE, so a blank-vs-blank comparison would report :ok for precisely the
      # misconfiguration this check exists to catch.
      if configured.empty? || redis_url.to_s.empty?
        check.call("ActionCable adapter", :fail,
                   "cannot compare — cable.yml url=#{configured.empty? ? '(unset)' : configured}, " \
                   "REDIS_URL=#{redis_url.to_s.empty? ? '(unset)' : redis_url}")
      else
        same = configured.start_with?(redis_url.to_s) || redis_url.to_s.start_with?(configured)
        check.call("ActionCable adapter", same ? :ok : :warn,
                   same ? "redis, same endpoint as REDIS_URL" : "cable.yml points at #{configured}, REDIS_URL is #{redis_url}")
      end
    end

    # --- Scorecard ---------------------------------------------------------
    fails = results.count { |s, _, _| s == :fail }
    warns = results.count { |s, _, _| s == :warn }
    puts "\n#{fails.zero? ? '🟢' : '🔴'} dr:verify_data_tier — #{results.size} checks: " \
         "#{results.size - fails - warns} ok, #{warns} warnings, #{fails} failures"
    abort "❌ dr:verify_data_tier FAILED on #{Socket.gethostname} (see above)" if fails.positive?
  end
end
