# See rack-attack.rb for more details
require_relative '../../lib/middleware/log_404s' # Ensure this matches your file path
Rails.application.config.middleware.insert_before(Rack::Attack, Log404s)

module Rack
  class Attack
    ### Configure Cache ###

    # If you don't want to use Rails.cache (Rack::Attack's default), then
    # configure it here.
    #
    # Note: The store is only used for throttling (not blocklisting and
    # safelisting). It must implement .increment and .write like
    # ActiveSupport::Cache::Store

    # Rack::Attack's counters (this file's throttle/blocklist DSL, plus the
    # manual rack::attack:404:/:throttled:/:blocked: keys below and in
    # Log404s) used to share Rails.cache, which is Solid Cache/MySQL in
    # production. Under a 404-scanner storm that meant dozens of concurrent
    # `INSERT ... ON DUPLICATE KEY UPDATE`s into solid_cache_entries per
    # second, and MySQL's gap-locking on its unique key_hash index deadlocked
    # (mysql-error.log, 2026-09-25 — all deadlocking transactions were
    # solid_cache_entries inserts keyed "rack::attack:...:limit_404_errors:*").
    # Redis's atomic INCR/EXPIRE has no equivalent lock, so give Rack::Attack
    # its own Redis-backed store instead — namespaced so its keys can't
    # collide with Sidekiq's or Action Cable's on the same Redis instance.
    # Every other Rails.cache call in the app (fragment/query caching, etc.)
    # is untouched and stays on Solid Cache.
    #
    # Redis is opted INTO for the deployed environments, rather than opted out
    # of for test. Development and test keep plain Rails.cache:
    #   * test — @rack_attack cucumber scenarios swap Rails.cache to a fresh
    #     MemoryStore and mirror it onto Rack::Attack.cache.store themselves
    #     (features/support/rack_attack.rb); forcing Redis here would fight
    #     that swap, and the travel_to scenarios cannot expire a real Redis
    #     TTL. The Redis store gets its own coverage instead —
    #     features/security/rack_attack_404_blocking_redis.feature.
    #   * development — cache_store is :null_store unless tmp/caching-dev.txt
    #     exists, so these counters have always been inert locally. Pointing
    #     dev at Redis buys nothing (dev traffic is 127.0.0.1, safelisted
    #     below, so the rules can never fire) and costs a Redis round trip per
    #     404 — or a full connect timeout per request with no local Redis up.
    Rack::Attack.cache.store =
      if Rails.env.production? || Rails.env.staging?
        ActiveSupport::Cache::RedisCacheStore.new(
          # NO default, deliberately. This store backs a SECURITY control and
          # every Redis failure fails OPEN (see the timeouts below), so a
          # missing REDIS_URL would quietly point at a non-existent localhost
          # Redis and switch OFF every throttle plus the 404 blocklist —
          # visible only as "RedisCacheStore: read failed" log lines. Better
          # to refuse to boot. REDIS_URL is set in .env.production.* /
          # .env.staging.* (aws_utils.rb's update_env_file writes it).
          url: ENV.fetch('REDIS_URL'),
          namespace: 'rack_attack',
          pool: { size: ENV.fetch('RAILS_MAX_THREADS', 5).to_i, timeout: 5 },
          # Rack::Attack runs INSIDE the request path, so a Redis outage has
          # to cost milliseconds, not seconds. ActiveSupport's defaults are 1s
          # per timeout and redis-rb retries a failed connect once, so a dead
          # Redis would add ~2s per store op — and the 404 rules below do up
          # to 3 ops per anonymous request, i.e. ~6s of dead weight on every
          # request. RedisCacheStore#failsafe rescues Redis::BaseError and
          # returns nil regardless (nil.to_i == 0 => no throttle, no block),
          # so the behaviour on an outage is already fail-open; these settings
          # only bound how slowly it fails.
          connect_timeout: 0.2, read_timeout: 0.2, write_timeout: 0.2,
          reconnect_attempts: 0
        )
      else
        Rails.cache
      end

    # Enabled in ALL environments, including test: the @rack_attack cucumber
    # scenarios exercise these rules end-to-end. This is safe for the rest of
    # the test suite because Capybara/Playwright traffic originates from
    # 127.0.0.1 with no X-Forwarded-For (covered by the localhost safelist
    # below), and the test env's :null_store cache keeps all counters inert
    # except where a scenario swaps in a real store.

    # SECURITY (finding M4): the previous global safelist exempted ANY request carrying a session
    # cookie from ALL throttles — including the login brute-force and 404-scanner throttles below —
    # so a single low-privilege authenticated session bypassed every rate limit. Removed. Logged-in
    # users are instead exempted only from the GENERAL per-IP throttle (see the `req/ip` rule), while
    # the login and 404 throttles now apply to everyone, authenticated or not.
    def self.logged_in?(req)
      # SECURITY: cookie PRESENCE is not proof of authentication — a scanner
      # can attach any junk _caphive_session value and previously bypassed
      # these exemption checks (and real users with stale/undecryptable
      # cookies were misclassified). Rack::Attack runs after the session and
      # Warden middleware, so Log404s.authenticated? can decrypt the actual
      # session and require Devise's warden.user.* key, which only exists
      # after a successful sign-in.
      Log404s.authenticated?(req.env)
    end

    # The exact IP the Log404s middleware keys its 404 counter by (it uses
    # ActionDispatch::Request#remote_ip, which returns the value the RemoteIp
    # middleware memoized here). The 404 rules below MUST read with the same
    # derivation — Rack::Request#ip applies its own X-Forwarded-For logic and
    # can disagree behind multi-hop proxies, silently splitting writer and
    # reader onto different keys.
    def self.client_ip(req)
      (req.env['action_dispatch.remote_ip'] || req.ip).to_s
    end

    # The per-IP 404 strike count Log404s maintains, read at most ONCE per
    # request. Both 404 rules below need it and Rack::Attack evaluates the
    # blocklist before the throttle, so without this memo every anonymous
    # request paid two identical store reads — two Redis round trips, in the
    # request path, for one value.
    #
    # cache.store, NOT Rails.cache: Log404s writes this key via cache.store
    # too, and writer and reader must agree on the backing store or the
    # defense silently splits onto two disconnected copies of the key.
    #
    # read, NOT fetch-with-block: fetch writes its 0 default with no TTL on a
    # miss, and since this runs on every request it pre-created the key before
    # Log404s ever saw a 404 — which skipped Log404s' expiring first write and
    # made every per-IP counter permanent (nil.to_i is 0 anyway).
    #
    # Memoized in req.env, like Log404s.authenticated?. 0 is truthy in Ruby,
    # so ||= caches a genuine "no strikes" answer instead of re-reading it.
    def self.bad_request_count_for(req, ip)
      req.env['rack.attack.404_count'] ||=
        cache.store.read("rack::attack:404:#{ip}", raw: true).to_i
    end

    # Devise endpoints an anonymous user must always be able to reach to
    # (re)establish a session. Shared by the login brute-force throttles and
    # by the 404 scanner rules' skip-list below.
    AUTH_PATHS = ['/users/sign_in', '/users/reset_password', '/users/confirmation',
                  '/users/password', '/users/magic_link'].freeze

    # The second-factor screens sit between a correct password and a session: the user is
    # still anonymous to logged_in? but is exactly the "re-establishing a session" case the
    # 404 rules below exempt AUTH_PATHS for. Without this a user on a hot shared office/VPN
    # IP gets past sign-in (exempt) and is then 403'd on the code screen.
    #
    # An explicit list, exact-matched, for two reasons: the two resend endpoints
    # (/two_factor/send_sms, /two_factor/send_whatsapp) are deliberately NOT here — they
    # are not needed to establish a session and a blocked scanner must not keep reaching
    # a CSRF-exempt, paid send (send_sms also keeps its own throttle below); and a prefix
    # match would have exempted anything starting with the string.
    #
    # Deliberately NOT merged into AUTH_PATHS: the login throttles key on the email param,
    # which these requests do not carry.
    TWO_FACTOR_PAGE_PATHS = [
      '/two_factor',                            # POST: verify the login code
      '/two_factor/new',                        # GET:  login code screen
      '/two_factor/select_mode',                # GET + POST
      '/two_factor/enroll',                     # GET
      '/two_factor/verify_enrollment',          # POST
      '/two_factor/enroll_whatsapp',            # GET
      '/two_factor/verify_whatsapp_enrollment', # POST
      '/two_factor/enroll_sms',                 # GET
      '/two_factor/verify_sms_enrollment'       # POST
    ].freeze

    def self.auth_path?(req)
      AUTH_PATHS.include?(req.path) || TWO_FACTOR_PAGE_PATHS.include?(req.path)
    end

    # Loopback must never be throttled or blocked: puma sits behind nginx on a
    # unix socket, so requests WITHOUT X-Forwarded-For (ALB health checks,
    # monit, dr:verify's localhost curls) all resolve to req.ip == 127.0.0.1.
    # Without this, a scanner-driven 404 flood attributed to the shared
    # loopback identity (see Log404s) trips the blocklist below and the ALB
    # sees 403 on its health checks — marking every target unhealthy and
    # taking the site down. External clients keep their real XFF-derived IPs
    # and are policed normally.
    safelist('localhost') do |req|
      ['127.0.0.1', '::1'].include?(req.ip)
    end

    Rack::Attack.throttled_responder = lambda do |req|
      Rails.logger.warn "⚠️ Throttled request from #{req.ip} on rule #{req.env['rack.attack.matched']}"
      [429, { 'Content-Type' => 'text/plain' }, ["Rate limit exceeded. Try again later.\n"]]
    end

    ### Throttle Spammy Clients ###

    # If any single client IP is making tons of requests, then they're
    # probably malicious or a poorly-configured scraper. Either way, they
    # don't deserve to hog all of the app server's CPU. Cut them off!
    #
    # Note: If you're serving assets through rack, those requests may be
    # counted by rack-attack and this throttle may be activated too
    # quickly. If so, enable the condition to exclude them from tracking.

    # Throttle all requests by IP (60rpm)
    #
    # Key: "rack::attack:#{Time.now.to_i/:period}:req/ip:#{req.ip}"
    # SECURITY (finding M4): logged-in users are exempted from THIS general throttle only (so normal
    # authenticated browsing isn't rate-limited), but they remain subject to the login and 404
    # throttles below.
    throttle('req/ip', limit: 300, period: 5.minutes) do |req|
      req.ip unless logged_in?(req)
    end

    ### Prevent Brute-Force Login Attacks ###

    # The most common brute-force login attack is a brute-force password
    # attack where an attacker simply tries a large number of emails and
    # passwords to see if any credentials match.
    #
    # Another common method of attack is to use a swarm of computers with
    # different IPs to try brute-forcing a password for a specific account.

    # Throttle POST requests to /login by IP address
    #
    # Key: "rack::attack:#{Time.now.to_i/:period}:logins/ip:#{req.ip}"
    throttle('logins/ip', limit: 10, period: 30.seconds) do |req|
      if req.ip && AUTH_PATHS.include?(req.path) && req.post?
        # Rails.logger.info "🔍 Throttle check: IP #{req.ip} requested login page"
        # count_key = "rack::attack:#{(Time.now.to_i / 30)}:logins/ip:#{req.ip}"
        # current_count = Rails.cache.read(count_key) || 0
        # Rails.logger.info "Throttle count for IP #{req.ip}: #{current_count}"
        req.ip
      end
    end

    # Throttle POST requests to /login by email param
    #
    # Key: "rack::attack:#{Time.now.to_i/:period}:logins/email:#{normalized_email}"
    #
    # Note: This creates a problem where a malicious user could intentionally
    # throttle logins for another user and force their login requests to be
    # denied, but that's not very common and shouldn't happen to you. (Knock
    # on wood!)
    throttle('block_bad_sign_ins', limit: 10, period: 30.seconds) do |req|
      if AUTH_PATHS.include?(req.path) && req.post?
        # SECURITY (finding M4): Devise and the magic-link form submit the address as user[email],
        # so the previous req.params['email'] was always nil and this per-email throttle never fired.
        # Read the nested param (with a flat fallback) so per-account credential stuffing is limited.
        # Normalize identically to the authentication path to prevent rate-limit bypass via casing.
        (req.params.dig('user', 'email') || req.params['email']).to_s.downcase.gsub(/\s+/, "").presence
      end
    end

    # Throttle the two-factor SMS send endpoint by IP.
    #
    # Every request here costs real money — it sends a text message. SMS pumping (toll
    # fraud) is the standard attack: drive sends to premium-rate numbers and take a cut
    # of the termination fee. This is the per-IP layer of a three-layer defence; the
    # per-number and per-user layers are durable counters inside TwilioSmsDelivery,
    # which is where the money is actually stopped. This one catches a single actor
    # driving many accounts before the request reaches Rails at all.
    #
    # Deliberately NOT added to AUTH_PATHS: that list exempts paths from the 404 scanner
    # rules because an anonymous user must be able to reach them to sign in. This
    # endpoint is not needed to establish a session — it is an optional resend — so it
    # gets no such exemption.
    #
    # Tighter than logins/ip (10 per 30s) because a legitimate user presses resend once
    # or twice, never ten times.
    #
    # @see docs/modules/two_factor_auth/twilio_sms_otp_design.md section 9
    # start_with? rather than ==: `post :send_sms` inside `resource :two_factor` generates
    # /two_factor/send_sms(.:format), so /two_factor/send_sms.json reaches the same action.
    # An exact match would compute no throttle key at all for that request.
    throttle('otp_sms_send/ip', limit: 3, period: 60.seconds) do |req|
      client_ip(req) if req.post? && req.path.start_with?('/two_factor/send_sms')
    end

    # Throttle the public demo-form endpoint by IP.
    #
    # This is the only unauthenticated, CSRF-exempt write endpoint in the app
    # (WebsiteLeadsController#create), reachable cross-origin from the static
    # website. The honeypot and the time-to-submit check inside WebsiteLeadCreate
    # stop a naive bot; this stops a determined one from filling the table.
    #
    # 5 per hour is deliberately generous against real demand of a handful of
    # demo requests per month, so the only way a genuine visitor trips it is by
    # submitting the same form five times — at which point they have our
    # attention anyway.
    #
    # Deliberately NOT added to AUTH_PATHS: that list exempts paths from the 404
    # scanner rules because an anonymous user must reach them to sign in. This
    # endpoint is not needed to establish a session.
    #
    # Exact == rather than start_with?: /website_leads/:id is the STAFF-only show
    # page and must not share a throttle bucket with anonymous submissions. Only
    # POSTs are counted, so the staff index (a GET on the same path) is untouched.
    #
    # @see docs/modules/website/website_lead_capture.md
    throttle('website_leads/ip', limit: 5, period: 1.hour) do |req|
      client_ip(req) if req.post? && req.path == '/website_leads'
    end

    # Throttle IPs that hit 404 errors multiple times
    # Action	Effect
    # Attacker sends 5 requests	Allowed
    # Sends the 6th request within 10 seconds	Blocked for 5 minutes
    # Attacker waits 10 seconds	Still blocked (not reset)
    # Attacker tries again after 5 minutes	Allowed again
    throttle('limit_404_errors', limit: 5, period: 10.seconds) do |req|
      # SECURITY (finding M4 follow-up): the 404 scanner defenses target unauthenticated probes.
      # Authenticated humans routinely generate benign 404s (missing assets, stale Turbo/AJAX
      # endpoints, deleted records) and often share a NATed office/VPN IP, so applying this
      # IP-keyed block to them mass-blocked real users. Exempt logged-in users here; they remain
      # subject to the login brute-force throttle above, which is what finding M4 required.
      next nil if logged_in?(req)

      # A valid user with an EXPIRED session is anonymous until they sign in
      # again. If their shared NAT/VPN IP is hot (a scanner on the same IP, or
      # stale tabs spraying 404s), gating the auth endpoints here would lock
      # them out of ever re-authenticating — the login endpoints have their
      # own brute-force throttles above, so let them through.
      next nil if auth_path?(req)

      ip = client_ip(req)

      bad_request_count = bad_request_count_for(req, ip)
      throttle_request = bad_request_count > 5

      if throttle_request
        Rails.logger.info "rack::attack: Throttling IP #{ip} after #{bad_request_count} 404s"
        Rails.logger.debug { "rack::attack:throttled:#{ip} #{cache.store.read("rack::attack:throttled:#{ip}")}" }

        # Store a throttle flag for 5 minutes
        cache.store.write("rack::attack:throttled:#{ip}", true, expires_in: 5.minutes)
      end

      # Return true if the IP is currently throttled
      cache.store.read("rack::attack:throttled:#{ip}").present? ? ip : nil
    end

    # Action	Effect
    # Attacker sends 10 requests	Not blocked yet
    # Attacker sends the 11th request	Blocked for 10 minutes
    # After 10 minutes, they can try again	Can request again
    blocklist('block_ip_after_repeated_404s') do |req|
      # SECURITY (finding M4 follow-up): see limit_404_errors above — exempt authenticated users
      # from the IP-keyed 404 blocklist so shared-IP logged-in users are not mass-blocked. The
      # login brute-force throttle still applies to them.
      next false if logged_in?(req)

      # Never 403 the auth endpoints — see limit_404_errors above: a blocked
      # anonymous user must always be able to reach sign-in to become an
      # authenticated (exempt) one. Login abuse is handled by the dedicated
      # login throttles.
      next false if auth_path?(req)

      ip = client_ip(req)

      bad_request_count = bad_request_count_for(req, ip)
      block_request = bad_request_count > 10

      if block_request
        Rails.logger.info "rack::attack:Blocking IP #{ip} after #{bad_request_count} 404s"
        Rails.logger.debug { "rack::attack:blocked:#{ip} #{cache.store.read("rack::attack:blocked:#{ip}")}" }

        # Store a block flag for 5 minutes
        cache.store.write("rack::attack:blocked:#{ip}", true, expires_in: 5.minutes)
      end

      # Return true if IP is in the blocked list
      cache.store.read("rack::attack:blocked:#{ip}").present?
    end

    ### Custom Throttle Response ###

    # By default, Rack::Attack returns an HTTP 429 for throttled responses,
    # which is just fine.
    #
    # If you want to return 503 so that the attacker might be fooled into
    # believing that they've successfully broken your app (or you just want to
    # customize the response), then uncomment these lines.
    # self.throttled_response = lambda do |env|
    #  [ 503,  # status
    #    {},   # headers
    #    ['']] # body
    # end
  end
end
