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
      ip = env['REMOTE_ADDR']
      key = "rack::attack:404:#{ip}"
    
      if Rails.cache.exist?(key)
        new_count = Rails.cache.increment(key, 1)
      else
        Rails.cache.write(key, 1, expires_in: 1.minute)
        new_count = 1
      end
    
      Rails.logger.debug "Log404s: 404 count for IP #{ip} is now #{new_count}"
    end
    

    [status, headers, response]
  end
end
