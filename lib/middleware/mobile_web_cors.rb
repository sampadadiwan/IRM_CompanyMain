# frozen_string_literal: true

# CORS for the LP mobile app's WEB review build only (Expo web on e.g. http://localhost:8081
# calling this Rails server). The real iOS / Android apps are not browsers and need no CORS.
#
# Off unless MOBILE_WEB_ORIGIN is set, and never inserted in production (config/application.rb).
# Allows exactly that one origin, bearer-token requests only — no cookies.
class MobileWebCors
  def initialize(app, origin)
    @app = app
    @origin = origin
  end

  def call(env)
    return @app.call(env) unless env["HTTP_ORIGIN"] == @origin

    if env["REQUEST_METHOD"] == "OPTIONS"
      [204, cors_headers, []]
    else
      status, headers, body = @app.call(env)
      [status, headers.merge(cors_headers), body]
    end
  end

  private

  def cors_headers
    {
      "access-control-allow-origin" => @origin,
      "access-control-allow-methods" => "GET, POST, PUT, PATCH, DELETE, OPTIONS",
      "access-control-allow-headers" => "Authorization, Content-Type, Accept, Accept-Language, X-App-Version",
      "access-control-max-age" => "600",
      "vary" => "Origin"
    }
  end
end
