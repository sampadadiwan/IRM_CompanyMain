class Log404s
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      status, headers, response = @app.call(env)
    rescue => e
      Rails.logger.error "Log404s middleware error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-raise after logging
    end

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
