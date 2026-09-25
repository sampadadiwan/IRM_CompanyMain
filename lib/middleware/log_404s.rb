# ─────────────────────────────────────────────────────────────────────────────
# FAQ — 404-scanner defense (this middleware + config/initializers/rack_attack.rb)
#
# Q: What does this middleware actually do?
# A: It only COUNTS. Every 404 served to an unauthenticated client increments
#    a per-IP counter ("rack::attack:404:<ip>", 1-minute TTL). The
#    ENFORCEMENT lives in rack_attack.rb: >5 404s throttles the IP (429),
#    >10 blocks it (403 "Forbidden") for 5 minutes. So if users report 403s,
#    look at the Rack::Attack rules, not just this file.
#
# Q: Why key by remote_ip instead of REMOTE_ADDR?
# A: Puma sits behind nginx on a unix socket, so REMOTE_ADDR is 127.0.0.1 for
#    every proxied request. Keying by it pooled all scanners onto one loopback
#    counter — which then blocklisted ALB health checks and took the site
#    down. remote_ip resolves the real client via X-Forwarded-For. The
#    Rack::Attack rules read with the same derivation (client_ip) — writer
#    and reader MUST agree or the defense silently splits onto two keys.
#
# Q: Why check the decrypted session instead of cookie presence?
# A: Both directions failed before. A scanner can attach any junk
#    _caphive_session value, so cookie presence granted attackers the
#    logged-in exemption; meanwhile stale/expired cookies misclassified real
#    users. Devise's "warden.user.<scope>.key" only exists in a session that
#    actually decrypted after a successful sign-in — spoof-proof both ways.
#
# Q: Why skip counting for authenticated users at all?
# A: Real users generate benign 404s constantly (stale Turbo/AJAX endpoints,
#    deleted records, missing assets) and often share one NATed office/VPN
#    IP. Counting them poisoned that shared IP: the moment anyone's session
#    expired they were 403'd — including on the sign-in page, so they could
#    never re-authenticate. That lockout also drives the AUTH_PATHS skip in
#    rack_attack.rb: the 404 rules never gate the Devise endpoints (login
#    abuse has its own brute-force throttles).
#
# Q: Why raw: true and expires_in on EVERY increment?
# A: raw keeps the value increment-compatible and matches the raw: true reads
#    in rack_attack.rb (a marshalled write reads back as garbage there). The
#    TTL used to be set only on a first-write branch that never executed,
#    because rack_attack.rb's fetch-with-block pre-created the key with NO
#    TTL on every request — making every counter permanent, so an IP that
#    ever crossed the threshold stayed blocked forever. Hence: increment
#    always carries the TTL, and rack_attack.rb reads with cache.read (which
#    can never create a key), never fetch.
#
# Q: Why Rack::Attack.cache.store instead of Rails.cache?
# A: rack_attack.rb points Rack::Attack.cache.store at a dedicated Redis store
#    in production/staging and leaves it on Rails.cache in development/test
#    (see its comment there) — this counter and the throttle/blocklist rules
#    that read it (limit_404_errors, block_ip_after_repeated_404s) must all
#    agree on the same backing store, or the count silently splits into two
#    disconnected copies. Never reach for Rails.cache here: in production the
#    two are DIFFERENT stores (Redis vs Solid Cache), so the bug would only
#    ever show up in production, where the counter would read as 0 forever.
#
# Q: An IP is wrongly blocked in production right now — how do I clear it?
# A: These counters live in Rack::Attack's own Redis-backed store (see
#    config/initializers/rack_attack.rb), not Solid Cache. In a prod console:
#      store = Rack::Attack.cache.store
#      store.delete("rack::attack:404:<ip>")
#      store.delete("rack::attack:throttled:<ip>")
#      store.delete("rack::attack:blocked:<ip>")
#    Blocks also self-expire ~5 minutes after the 404s stop.
#
# Q: How is all of this tested?
# A: features/security/rack_attack_404_blocking.feature (@rack_attack) runs
#    scanners and valid users through the full middleware stack, including
#    spoofed cookies, shared IPs, sign-in-while-blocked, and expiry. Note
#    Rack::Attack is ENABLED in the test env; scenarios get a real cache via
#    features/support/rack_attack.rb.
#
#    That suite runs on a MemoryStore, which proves the RULES but nothing
#    about the store production actually uses, so
#    rack_attack_404_blocking_redis.feature (@rack_attack_redis) re-runs the
#    core block/throttle/exemption path against a real Redis-backed
#    RedisCacheStore. That is the configuration where rack-attack wraps the
#    store in RedisCacheStoreProxy (which forces raw: true on read AND write)
#    and where the namespace and the INCR-set TTL apply — none of which the
#    MemoryStore path exercises. It needs a local Redis on REDIS_URL.
# ─────────────────────────────────────────────────────────────────────────────
class Log404s
  # Devise (via Warden) writes "warden.user.<scope>.key" into the session only
  # after a successful sign-in, so its presence proves a VALID session — unlike
  # mere presence of the _caphive_session cookie, which any scanner can fake
  # with a junk value and which also lingers in browsers as a stale cookie.
  WARDEN_KEY_PREFIX = "warden.user.".freeze

  # Shared with rack_attack.rb's logged_in? exemptions. Both this middleware
  # and Rack::Attack sit AFTER ActionDispatch::Session::CookieStore in the
  # stack, so env['rack.session'] is available; to_hash triggers the lazy
  # load/decryption, and a tampered or bogus cookie decrypts to an empty
  # session, correctly reading as NOT authenticated.
  def self.authenticated?(env)
    # Memoized in env: this is consulted by three Rack::Attack rules plus this
    # middleware on the same request, and each uncached call decrypts the
    # session cookie.
    return env['log404s.authenticated'] if env.key?('log404s.authenticated')

    env['log404s.authenticated'] = begin
      session = env['rack.session']
      if session
        session.to_hash.keys.any? { |k| k.to_s.start_with?(WARDEN_KEY_PREFIX) }
      else
        false
      end
    rescue => e
      # A session we cannot read is treated as unauthenticated rather than
      # letting an error here take down the whole request.
      Rails.logger.warn "Log404s: session check failed - #{e.class}: #{e.message}"
      false
    end
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    status = nil
    headers = {}
    response = []

    begin
      status, headers, response = @app.call(env)
    rescue ActionDispatch::Http::MimeNegotiation::InvalidType => e
      Rails.logger.warn "Log404s middleware: InvalidType error caught - #{e.message}"
      # Set status to 404 to trigger the 404 logging block, but return 406 to the client
      status = 404
      headers = { 'Content-Type' => 'text/plain' }
      response = ['406 Not Acceptable']
    rescue ActionController::BadRequest => e
      Rails.logger.warn "Log404s middleware: BadRequest error caught - #{e.message}"
      # Set status to 404 to trigger the 404 logging block, but return 400 to the client
      status = 404
      headers = { 'Content-Type' => 'text/plain' }
      response = ['400 Bad Request']
    rescue => e
      Rails.logger.error "Log404s middleware error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-raise after logging
    end

    # This block will now execute if status is 404 (either from app.call or from InvalidType rescue)
    if status == 404
      request = ActionDispatch::Request.new(env)

      # The 404 scanner defenses in rack_attack.rb exempt authenticated users
      # (see finding M4 follow-up there), so authenticated 404s must not be
      # COUNTED either: admins browsing normally generate benign 404s (stale
      # AJAX endpoints, deleted records, missing assets) and share NATed
      # office/VPN IPs — counting those 404s poisons the per-IP counter and
      # 403-blocks everyone from that IP, locking them out of the sign-in
      # page itself. Uses the decrypted-session Warden check (not cookie
      # presence) so scanners sending junk session cookies are still counted.
      unless self.class.authenticated?(env)
        # remote_ip resolves the real client through X-Forwarded-For. REMOTE_ADDR
        # is useless here: puma is behind nginx on a unix socket, so it is
        # 127.0.0.1 for EVERY proxied request — which pooled all scanners' 404s
        # onto one shared counter and got loopback (ALB health checks, local
        # monitoring) blocklisted instead of the actual abuser.
        ip = request.remote_ip
        key = "rack::attack:404:#{ip}"

        # raw: true keeps the value increment-compatible and matches the
        # raw: true reads in rack_attack.rb (a marshalled write reads back as
        # garbage there). expires_in on EVERY increment guarantees the counter
        # expires — previously the expiry was only set on first write, a branch
        # that never ran because rack_attack.rb's fetch-with-block had already
        # created the key (with no TTL), making every counter permanent.
        new_count = Rack::Attack.cache.store.increment(key, 1, raw: true, expires_in: 1.minute)
        if new_count.nil?
          # Some stores return nil when incrementing a missing key instead of
          # initializing it — seed the counter explicitly in that case.
          Rack::Attack.cache.store.write(key, 1, raw: true, expires_in: 1.minute)
          new_count = 1
        end

        Rails.logger.debug "Log404s: 404 count for IP #{ip} is now #{new_count}"
      end
    end


    [status, headers, response]
  end
end
