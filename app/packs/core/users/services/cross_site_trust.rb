# frozen_string_literal: true

# Lets two regions prove they still share the same CROSS_INSTANCE_SECRET, without either of
# them revealing it.
#
# The secret lives in per-region encrypted credentials (config/credentials/production.in.yml.enc
# and production.us.yml.enc are separate files with separate keys), so the two can silently
# diverge. When they do, EVERY region switch fails - and before this change it failed with the
# same "Invalid or expired link" a merely-expired credential produced, so the message invited
# the user to retry something that could never work.
#
# The fingerprint is an HMAC of a fixed, public probe string under the secret. Two regions'
# fingerprints are equal if and only if their secrets are equal, and the secret cannot be
# recovered from it.
class CrossSiteTrust
  # Public and non-secret on purpose: it is the message, not the key.
  PROBE = "caphive-cross-site-trust-v1"

  MISMATCH_CACHE_KEY = "cross_site_trust:mismatch"
  # Three missed hourly runs. A stale flag degrades to "no known mismatch", which reports a bad
  # signature as :invalid rather than :secret_mismatch - the safe direction, since it never
  # invents a configuration problem.
  MISMATCH_TTL = 90.minutes

  class << self
    def configured?
      secret.present?
    end

    # nil - not an HMAC of nil - when unconfigured, so two regions that both lack a secret can
    # never be mistaken for two regions that agree.
    def fingerprint
      return nil unless configured?

      OpenSSL::HMAC.hexdigest("SHA256", secret, PROBE)
    end

    # Read from cache only. A request path must never depend on the peer region being
    # reachable, so this is answered from what CrossSiteTrustCheckJob last wrote.
    def peer_mismatch?
      Rails.cache.read(MISMATCH_CACHE_KEY) == true
    rescue StandardError => e
      Rails.logger.warn("[cross_site_trust] cache read failed: #{e.class}: #{e.message}")
      false
    end

    def record_mismatch(mismatched)
      Rails.cache.write(MISMATCH_CACHE_KEY, mismatched, expires_in: MISMATCH_TTL)
    end

    def secret
      Rails.application.credentials[:CROSS_INSTANCE_SECRET].presence
    rescue StandardError
      nil
    end
  end
end
