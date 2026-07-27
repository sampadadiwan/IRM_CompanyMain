class Log404s
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
      # 403-blocks everyone from that IP the moment their session cookie
      # expires, locking them out of the sign-in page itself.
      session_cookie = request.cookies[Rails.application.config.session_options[:key]]
      unless session_cookie.present?
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
        new_count = Rails.cache.increment(key, 1, raw: true, expires_in: 1.minute)
        if new_count.nil?
          # Some stores return nil when incrementing a missing key instead of
          # initializing it — seed the counter explicitly in that case.
          Rails.cache.write(key, 1, raw: true, expires_in: 1.minute)
          new_count = 1
        end

        Rails.logger.debug "Log404s: 404 count for IP #{ip} is now #{new_count}"
      end
    end


    [status, headers, response]
  end
end
