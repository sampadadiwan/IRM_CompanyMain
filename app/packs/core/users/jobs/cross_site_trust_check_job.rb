# frozen_string_literal: true

# Hourly: ask every peer region for its inter-region secret fingerprint and compare it with
# ours, so a silent divergence becomes an alert instead of a wall of failed region switches.
#
# This runs in the background rather than during a rejection on purpose: a request path must
# never depend on another region being reachable. CrossSiteRejection only ever reads the flag
# this job writes.
class CrossSiteTrustCheckJob < ApplicationJob
  queue_as :sync

  # Matches SyncApiClient::DEFAULT_TIMEOUT - the other cross-region HTTP call in the app.
  TIMEOUT = 10

  # A misconfigured registry cannot be fixed by retrying, and the boot check has already
  # shouted about it.
  discard_on SiteRegistry::ConfigurationError

  def perform
    ours = CrossSiteTrust.fingerprint
    # No secret here means we cannot verify anything anyone signs, so treat it as a mismatch
    # rather than quietly reporting health.
    if ours.nil?
      Rails.logger.error("[cross_site_trust] no CROSS_INSTANCE_SECRET configured on #{SiteRegistry.current_code}")
      CrossSiteTrust.record_mismatch(true)
      SiteRegistry.peers.each { |peer| CrossSiteMetrics.trust(peer, false) }
      return
    end

    # map + compact, NOT filter_map: check_peer returns false for a divergent peer and nil for
    # an unreachable one, and filter_map drops both - which would silently discard the very
    # mismatch this job exists to catch. Only nil means "no verdict".
    # rubocop:disable Performance/MapCompact -- filter_map would drop the `false` verdicts too
    verdicts = SiteRegistry.peers.map { |peer| check_peer(peer, ours) }.compact
    # rubocop:enable Performance/MapCompact
    # .empty? and not .any?, for the same reason: [false].any? is false.
    return if verdicts.empty?

    # One divergent peer is enough to make a bad signature worth reporting as a configuration
    # problem rather than as tampering.
    CrossSiteTrust.record_mismatch(verdicts.include?(false))
  end

  private

  # Returns true (match), false (divergence) or nil (unreachable - deliberately NOT a verdict).
  def check_peer(peer, ours)
    response = HTTParty.get("#{SiteRegistry.url_for(peer)}/health_check/cross_site_trust",
                            timeout: TIMEOUT,
                            headers: { "Accept" => "application/json" })
    return unreachable(peer, "HTTP #{response.code}") unless response.code == 200

    body = JSON.parse(response.body)
    # A peer with no secret cannot verify what we sign, so that IS a verdict, not a timeout.
    unless body["configured"]
      Rails.logger.error("[cross_site_trust] peer #{peer} reports no shared secret configured")
      CrossSiteMetrics.trust(peer, false)
      return false
    end

    matched = ActiveSupport::SecurityUtils.secure_compare(body["fingerprint"].to_s, ours)
    Rails.logger.error("[cross_site_trust] fingerprint mismatch with peer #{peer}") unless matched
    CrossSiteMetrics.trust(peer, matched)
    matched
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError => e
    unreachable(peer, "#{e.class}: #{e.message}")
  end

  # An unreachable peer is not a divergent secret. Leave the previous flag alone and write no
  # gauge sample - the Grafana rule alerts on the ABSENCE of a recent sample instead, which is
  # a different and more honest signal than "trust is broken".
  def unreachable(peer, detail)
    Rails.logger.warn("[cross_site_trust] peer #{peer} unreachable (#{detail})")
    nil
  end
end
