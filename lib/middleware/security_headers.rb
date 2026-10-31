# frozen_string_literal: true

# Adds the security headers that are enforced from day one (docs/security/security_review_2026_10.md,
# L5), on every response that does not already carry them:
#
#   Content-Security-Policy: object-src 'none'; base-uri 'self'; frame-ancestors 'self'
#     The full policy is still report-only (config/initializers/content_security_policy.rb). Rails
#     builds only ONE CSP header per response and skips it when a controller has set its own, so
#     the enforced part is added here instead, outside Rails' CSP middleware on the way out.
#     A controller that set its own Content-Security-Policy (OutlookAddinController's Office
#     frame-ancestors allowlist) keeps it: only object-src / base-uri are appended when missing,
#     frame-ancestors is never touched (L5-3).
#
#   Permissions-Policy: microphone and fullscreen for our own pages (voice input, full-screen
#     viewers; fullscreen also for embedded guide videos), geolocation / USB / payment / motion
#     sensors for nobody. Written here in the current Permissions-Policy syntax: Rails'
#     permissions_policy DSL still emits the old Feature-Policy header, which browsers ignore.
#     Camera and clipboard are left alone — clipboard is used, and whether the e-sign iframes need
#     the camera is an open decision.
class SecurityHeaders
  CSP = "Content-Security-Policy"
  PERMISSIONS_POLICY = "Permissions-Policy"

  # Enforced CSP directives, in the order they are written
  ENFORCED_DIRECTIVES = {
    "object-src" => "'none'",
    "base-uri" => "'self'",
    "frame-ancestors" => "'self'"
  }.freeze

  # Directives appended to a controller's own CSP when it lacks them (never frame-ancestors)
  APPENDABLE_DIRECTIVES = %w[object-src base-uri].freeze

  PERMISSIONS = [
    "microphone=(self)",
    'fullscreen=(self "https://www.youtube.com")',
    "geolocation=()",
    "usb=()",
    "payment=()",
    "accelerometer=()",
    "gyroscope=()",
    "magnetometer=()"
  ].join(", ").freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    # L5-H — the enforced CSP, or the missing parts of a controller's own one (L5-3)
    headers[CSP] = enforced_csp(headers[CSP])
    # L5-H — Permissions-Policy, unless something upstream already chose one
    headers[PERMISSIONS_POLICY] ||= PERMISSIONS

    [status, headers, body]
  end

  private

  # The enforced policy for a response, given the CSP a controller may already have set
  def enforced_csp(existing)
    # No policy yet: the three enforced directives
    return ENFORCED_DIRECTIVES.map { |name, value| "#{name} #{value}" }.join("; ") if existing.blank?

    # A controller's own policy: keep every directive it wrote, add only what it is missing
    present = existing.split(";").map { |part| part.strip.split(/\s+/).first.to_s.downcase }
    missing = APPENDABLE_DIRECTIVES.reject { |name| present.include?(name) }
    ([existing.strip.chomp(";")] + missing.map { |name| "#{name} #{ENFORCED_DIRECTIVES.fetch(name)}" }).join("; ")
  end
end
