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

    Rack::Attack.cache.store = Rails.cache

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

    # Devise endpoints an anonymous user must always be able to reach to
    # (re)establish a session. Shared by the login brute-force throttles and
    # by the 404 scanner rules' skip-list below.
    AUTH_PATHS = ['/users/sign_in', '/users/reset_password', '/users/confirmation',
                  '/users/password', '/users/magic_link'].freeze

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
    # @see docs/technical/twilio_sms_otp_design.md section 9
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
    # @see docs/technical/website_lead_capture.md
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
      next nil if AUTH_PATHS.include?(req.path)

      ip = client_ip(req)

      # read, NOT fetch-with-block: fetch writes its 0 default with no TTL on
      # a miss, and since this runs on every request it pre-created the key
      # before Log404s ever saw a 404 — which skipped Log404s' expiring first
      # write and made every per-IP counter permanent (nil.to_i is 0 anyway).
      bad_request_count = Rails.cache.read("rack::attack:404:#{ip}", raw: true).to_i
      throttle_request = bad_request_count > 5

      if throttle_request
        Rails.logger.info "rack::attack: Throttling IP #{ip} after #{bad_request_count} 404s"
        Rails.logger.debug { "rack::attack:throttled:#{ip} #{Rails.cache.read("rack::attack:throttled:#{ip}")}" }

        # Store a throttle flag for 5 minutes
        Rails.cache.write("rack::attack:throttled:#{ip}", true, expires_in: 5.minutes)
      end

      # Return true if the IP is currently throttled
      Rails.cache.read("rack::attack:throttled:#{ip}").present? ? ip : nil
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
      next false if AUTH_PATHS.include?(req.path)

      ip = client_ip(req)

      # read, NOT fetch-with-block — see limit_404_errors above: fetch's
      # 0-default write had no TTL and made the counter permanent.
      bad_request_count = Rails.cache.read("rack::attack:404:#{ip}", raw: true).to_i
      block_request = bad_request_count > 10

      if block_request
        Rails.logger.info "rack::attack:Blocking IP #{ip} after #{bad_request_count} 404s"
        Rails.logger.debug { "rack::attack:blocked:#{ip} #{Rails.cache.read("rack::attack:blocked:#{ip}")}" }

        # Store a block flag for 5 minutes
        Rails.cache.write("rack::attack:blocked:#{ip}", true, expires_in: 5.minutes)
      end

      # Return true if IP is in the blocked list
      Rails.cache.read("rack::attack:blocked:#{ip}").present?
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
