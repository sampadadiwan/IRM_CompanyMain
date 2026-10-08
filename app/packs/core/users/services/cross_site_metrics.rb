# frozen_string_literal: true

# The two Prometheus series this feature needs, and nothing else.
#
# Before these, a failed region switch left no trace at all: UsersController rendered a bare
# "Invalid or expired link" and wrote no log line, so nobody could tell a user's slow connection
# apart from a drifted clock or a divergent shared secret. The counter makes "expired is
# climbing" visible without reading logs; the gauge is what alerts when the two regions stop
# trusting each other.
#
# prometheus_exporter is already running on 9394 on every app server (config/schedule.rb at
# boot, config/deploy.rb as a restart guard) and Prometheus already scrapes it as the
# `rails_app` job in both regions, so a RemoteMetric registered against the default client
# works unchanged across Puma workers - no shared-memory store, no custom collector.
#
# Every call here swallows its own failure. A metrics outage must never fail a user's login,
# which is the one place in this change where a rescue deliberately does not re-raise.
class CrossSiteMetrics
  HANDOFF_NAME = "caphive_cross_region_handoff_total"
  TRUST_NAME   = "caphive_cross_region_trust"

  class << self
    # result: :ok | :rejected. reason: a CrossSiteRejection reason, or nil on success.
    # Label values are drawn from closed sets only - never an email, host or raw param - so
    # cardinality stays at (2 results x 7 reasons x number of regions).
    def handoff(result:, region:, reason: nil)
      guard do
        handoff_counter&.observe(1, result: result.to_s, reason: reason.to_s.presence || "none",
                                    region: region.to_s)
      end
    end

    # ok: true when this region's shared secret matches that peer's.
    def trust(peer_code, ok)
      guard { trust_gauge&.observe(ok ? 1 : 0, peer: peer_code.to_s) }
    end

    private

    def handoff_counter
      @handoff_counter ||= register(:counter, HANDOFF_NAME, "Cross-region hand-off outcomes")
    end

    def trust_gauge
      @trust_gauge ||= register(:gauge, TRUST_NAME,
                                "1 when this region's inter-region secret matches the peer's")
    end

    # Registration itself can fail when the exporter process is not up (development, test, a
    # box mid-deploy), so it is guarded exactly like an observation.
    def register(type, name, help)
      return nil unless defined?(PrometheusExporter::Client)

      PrometheusExporter::Client.default.register(type, name, help)
    rescue StandardError => e
      Rails.logger.warn("[cross_site_metrics] could not register #{name}: #{e.class}: #{e.message}")
      nil
    end

    def guard
      yield
      nil
    rescue StandardError => e
      Rails.logger.warn("[cross_site_metrics] #{e.class}: #{e.message}")
      nil
    end
  end
end
