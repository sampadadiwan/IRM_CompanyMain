class Log404s
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    if status == 404
      ip = env['REMOTE_ADDR']
      key = "rack::attack:404:#{ip}"

      # puts "404 error from IP: #{ip}, added to cache with key: #{key}"

      # Ensure Redis or Rails.cache is used correctly
      Rails.cache.increment(key, 1) # Increment the counter
      Rails.logger.debug "Log404s: Incrementing 404 counter for IP #{ip}: current count = #{Rails.cache.read(key)}"

      Rails.cache.write(key, 1, expires_in: 1.minutes) unless Rails.cache.exist?(key)
    end

    [status, headers, response]
  end
end
