# Serves the static company website (public/website/, mirrored from the
# ../caphive.com repo by `rake website:sync`) when a request arrives on the
# bare/apex domain instead of a tenant subdomain.
#
# Activation is STRICTLY opt-in via ENV["WEBSITE_HOSTS"] (comma-separated;
# the FIRST entry is the canonical host, every other listed host 301s to it,
# e.g. "caphive.com,www.caphive.com"). Deriving hosts from BASE_DOMAIN would
# hijack development and the whole Cucumber suite — both run on plain
# `localhost` — so an unset variable makes this middleware a pass-through
# no-op. Both production stacks opt in (.env.production.in / .us).
#
# Inserted at position 0 of the middleware stack (config/initializers/
# website.rb), ahead of ActionDispatch::Static, the session store and
# Log404s/Rack::Attack. That ordering matters:
#   * ActionDispatch::Static mounts with index: "index", so anything under
#     public/ would otherwise be served for EVERY hostname — website content
#     must only ever be reachable through this host gate;
#   * the shared `domain: :all` session cookie is never set for anonymous
#     website traffic (we short-circuit before the session store);
#   * scanners hammering the apex can't feed the per-IP 404 counters that
#     protect the app (Log404s / rack_attack.rb).
# The accepted trade-off of sitting above Rack::Attack: an IP the app has
# blocklisted can still fetch website pages through this middleware. That is
# bounded — misses answer from a memoized in-memory 404 body (no disk I/O)
# and hits are plain static file reads, the same work nginx would do — and in
# production nginx serves the apex before puma is ever involved.
#
# Because we short-circuit before ActionDispatch::SSL, this middleware
# re-implements the two force_ssl behaviors that matter for a public page:
# an http->https redirect and an HSTS header (deliberately WITHOUT
# includeSubDomains — the apex must not dictate policy for tenant hosts).
#
# In production nginx serves the apex directly from public/website (see
# config/deploy/templates/nginx_conf.erb), so this middleware is the
# dev/test server and a production fallback. Full design:
# docs/technical/website_serving.md
class Website
  # Matches Entity#sub_domain values; anything else in ?sub_domain= is
  # ignored rather than reflected into a redirect Location.
  SUB_DOMAIN_FORMAT = /\A[a-z0-9-]+\z/i
  HSTS_VALUE = "max-age=63072000".freeze # 2 years, no includeSubDomains

  def initialize(app)
    @app = app
    @root = Rails.public_path.join("website")
    # ActionDispatch::FileHandler (the same class ActionDispatch::Static
    # uses) gives us percent-decoding + clean_path_info traversal protection,
    # MIME types, Range support, "/" -> index.html AND extensionless
    # resolution (/about -> about.html) for free.
    # 300s default TTL: the HTML files are unfingerprinted, so keep them
    # fresh enough that a content sync propagates quickly.
    @handler = ActionDispatch::FileHandler.new(
      @root.to_s,
      index: "index",
      headers: { "cache-control" => "public, max-age=300" }
    )
  end

  def call(env)
    # Read per request (cheap) so Cucumber's Around hook can toggle the
    # variable without rebuilding the middleware stack.
    hosts = website_hosts
    return @app.call(env) if hosts.empty?

    request = Rack::Request.new(env)
    host = request.host.to_s.downcase # Rack strips the port for us
    # Tenant subdomains, app.*, ALB health checks (Host: <ip>) and /cable all
    # fall through untouched.
    return @app.call(env) unless hosts.include?(host)

    canonical = hosts.first

    # Legacy notification-email links target the bare domain with
    # ?sub_domain=<tenant> and used to be redirected by
    # WithAuthentication#set_current_entity — keep those links alive by
    # forwarding them to the tenant subdomain before serving anything static.
    if (tenant = legacy_tenant_param(request))
      return redirect("#{scheme_for(request)}://#{tenant}.#{canonical}#{port_suffix(request)}#{request.fullpath}")
    end

    # www (or any other alias) -> canonical apex, preserving scheme, an
    # explicit port (dev runs on :3001 with no TLS listener) and path+query.
    if host != canonical
      return redirect("#{scheme_for(request)}://#{canonical}#{port_suffix(request)}#{request.fullpath}")
    end

    # Parity with the force_ssl guarantee the ActionDispatch::SSL middleware
    # would have provided further down the stack.
    if force_ssl? && request.scheme != "https"
      return redirect("https://#{canonical}#{request.fullpath}")
    end

    # A brochure site has no writable endpoints.
    unless %w[GET HEAD].include?(request.request_method)
      return [405, { "allow" => "GET, HEAD", "content-type" => "text/plain" }, ["Method Not Allowed"]]
    end

    if (response = @handler.attempt(env.dup))
      _, headers, = response
      # The website's assets are UNFINGERPRINTED (assets/css/caphive.css keeps
      # its name across redesigns) — cache for a day, never `expires max`.
      headers["cache-control"] = "public, max-age=86400" if request.path.start_with?("/assets/")
      headers["strict-transport-security"] ||= HSTS_VALUE if force_ssl?
      response
    else
      not_found(request.head?)
    end
  end

  private

  # The website ships its own styled 404 page; serve it with a REAL 404
  # status so crawlers don't index dead URLs. head_request: we sit above
  # Rack::Head, so we must strip the body for HEAD ourselves (content-length
  # still advertises the GET body size, as RFC 9110 allows).
  def not_found(head_request)
    body = not_found_body
    headers = {
      "content-type" => "text/html; charset=utf-8",
      "cache-control" => "no-cache",
      "content-length" => body.bytesize.to_s
    }
    headers["strict-transport-security"] = HSTS_VALUE if force_ssl?
    [404, headers, head_request ? [] : [body]]
  end

  # Memoized so scanner floods cost a hash lookup, not a disk read, and
  # guarded so a missing 404.html (sync not run yet) degrades to a plain
  # body instead of an Errno::ENOENT that nothing above us would rescue.
  def not_found_body
    @not_found_body ||= begin
      file = @root.join("404.html")
      file.exist? ? file.read : "<!doctype html><html><body><h1>404 Not Found</h1></body></html>"
    end
  end

  def redirect(location)
    [301, {
      "location" => location,
      "content-type" => "text/html",
      "cache-control" => "public, max-age=3600"
    }, []]
  end

  # ?sub_domain= from the query string only (request.params would also read
  # POST bodies); malformed query strings just mean "no tenant param".
  def legacy_tenant_param(request)
    value = begin
      request.GET["sub_domain"]
    rescue StandardError
      nil
    end
    value.downcase if value&.match?(SUB_DOMAIN_FORMAT)
  end

  # Honors X-Forwarded-Proto (set by nginx/the ALB) via Rack, upgraded to
  # https wherever the app enforces TLS.
  def scheme_for(request)
    force_ssl? ? "https" : request.scheme
  end

  # Keep an EXPLICIT port from the Host header (dev: caphive.localhost:3001);
  # production Host headers carry no port, so this is empty there.
  def port_suffix(request)
    explicit = request.env["HTTP_HOST"].to_s[/:(\d+)\z/, 1]
    explicit ? ":#{explicit}" : ""
  end

  def force_ssl?
    Rails.application.config.force_ssl
  end

  # "caphive.com, www.caphive.com" -> ["caphive.com", "www.caphive.com"].
  # Ports are stripped so dev values like caphive.localhost:3001 compare
  # equal to Rack's portless request.host.
  def website_hosts
    ENV["WEBSITE_HOSTS"].to_s.split(",")
                        .map { |h| h.strip.downcase.sub(/:\d+\z/, "") }
                        .reject(&:empty?)
  end
end
