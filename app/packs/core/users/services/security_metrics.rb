# frozen_string_literal: true

# M12 (OWASP review 2026-11) — one Prometheus counter for the events that signal an attack in progress, so Grafana
# can alert on them (config/initializers/observability/grafana_provision.yml, "Security …" rules).
#
# Before this, a password-guessing run, 2FA code guessing or an id sweep across other firms' records was refused
# quietly, request by request, and nobody was told. These counters answer "is something happening right now"; the
# security event trail (OpenSpec security-event-trail, M11) will answer "who did what".
#
#   caphive_security_events_total{event, reason}
#     event:  authorization_denied | throttled | sign_in_failed | two_factor_failed
#     reason: from a closed set only — an exception class, a Rack::Attack rule name, a Warden failure message —
#             never an email, user id, IP or path, so the number of series stays small
#
# Same transport as CrossSiteMetrics: a RemoteMetric on the default prometheus_exporter client (port 9394, scraped
# as the rails_app job in both regions). Every call swallows its own failure: a metrics outage must never fail a
# sign-in or a request.
class SecurityMetrics
  NAME = "caphive_security_events_total"
  EVENTS = %i[authorization_denied throttled sign_in_failed two_factor_failed].freeze

  class << self
    # @param event [Symbol] one of EVENTS
    # @param reason [#to_s] a value from a closed set (see above)
    def event(event, reason: nil)
      return unless EVENTS.include?(event)

      guard { counter&.observe(1, event: event.to_s, reason: reason.to_s.presence || "none") }
    end

    private

    def counter
      @counter ||= register
    end

    # Registration can fail when the exporter isn't running (development, test, a box mid-deploy)
    def register
      return nil unless defined?(PrometheusExporter::Client)

      PrometheusExporter::Client.default.register(:counter, NAME, "Security events: denials, throttles, failed sign-ins and 2FA codes")
    rescue StandardError => e
      Rails.logger.warn("[security_metrics] could not register #{NAME}: #{e.class}: #{e.message}")
      nil
    end

    def guard
      yield
    rescue StandardError => e
      Rails.logger.warn("[security_metrics] dropped an observation: #{e.class}: #{e.message}")
    end
  end
end
