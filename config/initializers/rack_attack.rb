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

    Rack::Attack.enabled = false if Rails.env.test?

    # If a request has the Rails session cookie, we assume it’s a normal user.
    safelist('logged_in_users') do |req|
      # The cookie key is usually something like "_your_app_session"
      req.cookies[Rails.application.config.session_options[:key]].present?
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
    throttle('req/ip', limit: 300, period: 5.minutes, &:ip)

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
    throttle('logins/ip', limit: 5, period: 30.seconds) do |req|
      if req.ip && req.path == '/users/sign_in' && req.get?
        # Rails.logger.info "🔍 Throttle check: IP #{req.ip} requested login page"
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
    throttle('block_bad_sign_ins', limit: 5, period: 30.seconds) do |req|
      if req.path == '/users/sign_in' && req.post?
        # Normalize the email, using the same logic as your authentication process, to
        # protect against rate limit bypasses. Return the normalized email if present, nil otherwise.
        req.params['email'].to_s.downcase.gsub(/\s+/, "").presence
      end
    end

    # Throttle IPs that hit 404 errors multiple times
    # Action	Effect
    # Attacker sends 5 requests	Allowed
    # Sends the 6th request within 10 seconds	Blocked for 5 minutes
    # Attacker waits 10 seconds	Still blocked (not reset)
    # Attacker tries again after 5 minutes	Allowed again
    throttle('limit_404_errors', limit: 5, period: 10.seconds) do |req|
      bad_request_count = Rails.cache.fetch("rack::attack:404:#{req.ip}", raw: true) { 0 }.to_i
      throttle_request = bad_request_count > 5

      if throttle_request
        Rails.logger.info "rack::attack: Throttling IP #{req.ip} after #{bad_request_count} 404s"
        Rails.logger.debug { "rack::attack:throttled:#{req.ip} #{Rails.cache.read("rack::attack:throttled:#{req.ip}")}" }

        # Store a throttle flag for 5 minutes
        Rails.cache.write("rack::attack:throttled:#{req.ip}", true, expires_in: 5.minutes)
      end

      # Return true if the IP is currently throttled
      Rails.cache.read("rack::attack:throttled:#{req.ip}").present? ? req.ip : nil
    end

    # Action	Effect
    # Attacker sends 10 requests	Not blocked yet
    # Attacker sends the 11th request	Blocked for 10 minutes
    # After 10 minutes, they can try again	Can request again
    blocklist('block_ip_after_repeated_404s') do |req|
      bad_request_count = Rails.cache.fetch("rack::attack:404:#{req.ip}", raw: true) { 0 }.to_i
      block_request = bad_request_count > 10

      if block_request
        Rails.logger.info "rack::attack:Blocking IP #{req.ip} after #{bad_request_count} 404s"
        Rails.logger.debug { "rack::attack:blocked:#{req.ip} #{Rails.cache.read("rack::attack:blocked:#{req.ip}")}" }

        # Store a block flag for 5 minutes
        Rails.cache.write("rack::attack:blocked:#{req.ip}", true, expires_in: 5.minutes)
      end

      # Return true if IP is in the blocked list
      Rails.cache.read("rack::attack:blocked:#{req.ip}").present?
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
