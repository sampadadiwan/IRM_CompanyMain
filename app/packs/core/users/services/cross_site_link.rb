# frozen_string_literal: true

# The cross-region hand-off credential: a signed, short-lived, single-use token that lets a user
# already signed in on one region be signed in on another without re-entering a password.
#
# Two things about this class used to make region switching fail intermittently and
# undiagnosably:
#
#   1. The lifetime was 30 seconds. The credential has to survive a redirect from India to the
#      US, a scheme upgrade, a second redirect to the tenant subdomain and a fresh TLS handshake
#      before anyone checks it. Any cold worker, slow link or modestly drifted server clock ate
#      the whole budget - and because MessageVerifier stamps an ABSOLUTE expiry using the
#      issuing box's clock and compares it against the verifying box's, clock skew between the
#      regions subtracted directly from those 30 seconds.
#
#   2. `verify` rescued StandardError and re-raised one VerificationError, so "expired",
#      "tampered", "wrong region" and "wrong purpose" all reached the controller as the same
#      thing and were rendered as the same "Invalid or expired link". Nobody could tell which
#      had happened, which is why the bug survived so long.
#
# Now: five minutes, and a typed Result with a closed set of reasons. Single use is enforced
# separately by CrossSiteLink::Nonce, which is what makes the longer window safe.
class CrossSiteLink
  # The only purpose this credential may carry. A token minted for anything else must not be
  # replayable here, which is what the purpose check buys.
  PURPOSE = :login

  # Five minutes, not thirty seconds: long enough to absorb a slow hop, a cold worker restart
  # and several minutes of clock drift; short enough that a leaked address is stale by the time
  # anyone finds it. The exposure of the longer window is bought back by single use.
  LIFETIME = 5.minutes

  # Closed set. Result.failure refuses anything else, which is what stops a future caller
  # quietly reintroducing a catch-all.
  REASONS = %i[missing invalid expired wrong_region].freeze

  # The outcome of reading a credential. Immutable, and carries the facts a caller needs
  # (who it is for, where it came from) without the caller touching the payload.
  class Result
    attr_reader :reason, :email, :origin_code

    def self.ok(email:, origin_code:)
      new(reason: nil, email: email, origin_code: origin_code)
    end

    # No origin_code on a failure: nothing inside an unreadable or expired credential can be
    # trusted or even decoded, so the "return to <region>" link is driven by the plain `from`
    # query parameter instead - see CrossSiteRejection.
    def self.failure(reason)
      raise ArgumentError, "unknown cross-site rejection reason #{reason.inspect}" unless REASONS.include?(reason)

      new(reason: reason, email: nil, origin_code: nil)
    end

    def initialize(reason:, email:, origin_code:)
      @reason = reason
      @email = email
      @origin_code = origin_code
      freeze
    end

    def ok?
      @reason.nil?
    end
  end

  # Makes a hand-off credential usable exactly once.
  #
  # Nested here rather than in cross_site_link/nonce.rb because config/application.rb globs
  # app/packs/**/ into autoload_paths, so every subdirectory is its own Zeitwerk root and a
  # file at cross_site_link/nonce.rb would have to define a top-level Nonce.
  #
  # This is what buys back the security of raising the credential's lifetime from 30 seconds to
  # 5 minutes. Before it, the same URL signed a user in as many times as it was opened for its
  # whole life, so a value recovered from browser history, a proxy log or a shared screen was a
  # reusable password. Now the first successful redemption kills it.
  #
  # The claim is taken on the sign-in hop ONLY, and only after every other check has passed, so
  # a credential rejected for being expired or aimed at the wrong region is not also burned.
  #
  # `unless_exist` is the atomic bit: Solid Cache implements it with a row lock
  # (SolidCache::Store::Api#write_entry -> entry_lock_and_write) in the region's own database,
  # which both of that region's app servers share. Two simultaneous presentations therefore
  # produce exactly one winner, and a credential consumed on one app server is already consumed
  # on the other.
  module Nonce
    KEY_PREFIX = "cross_site_handoff"

    # One minute of headroom over the credential's own lifetime, so the claim can never expire
    # while the credential it guards is still redeemable.
    TTL = CrossSiteLink::LIFETIME + 1.minute

    module_function

    # true when THIS call won the claim; false when it had already been claimed.
    def claim(token)
      # Fail closed: if the cache is unreachable we cannot prove the credential is unused, and
      # signing someone in on that basis is exactly the replay this guards against.
      Rails.cache.write(key_for(token), true, unless_exist: true, expires_in: TTL) == true
    rescue StandardError => e
      Rails.logger.error("[cross_site_nonce] claim failed: #{e.class}: #{e.message}")
      false
    end

    # The token is digested, never stored. A cache row is far less sensitive than a live
    # credential, and this keeps the credential out of one more place.
    def key_for(token)
      "#{KEY_PREFIX}:#{OpenSSL::Digest::SHA256.hexdigest(token.to_s)}"
    end
  end

  def initialize(secret: CrossSiteTrust.secret)
    raise ArgumentError, "CROSS_INSTANCE_SECRET is not configured" if secret.blank?

    @verifier = ActiveSupport::MessageVerifier.new(secret, digest: "SHA256")
  end

  # Mint a credential. `site` is where it may be redeemed, `from` is where the user is coming
  # from - the latter is carried so a SUCCESSFUL hand-off can be logged with both ends.
  #
  # Both codes are checked against SiteRegistry here rather than trusted from the caller: this
  # is the last point at which an undeployed region can be refused before a user is redirected
  # to a URL built from nil.
  def generate(email, purpose:, site:, from:, expires_in: LIFETIME)
    site_code = SiteRegistry.normalize(site)
    from_code = SiteRegistry.normalize(from)
    raise ArgumentError, "unknown destination region #{site.inspect}" unless SiteRegistry.known?(site_code)
    raise ArgumentError, "unknown origin region #{from.inspect}" unless SiteRegistry.known?(from_code)

    @verifier.generate({ email: email, purpose: purpose, site: site_code, from: from_code },
                       expires_in: expires_in)
  end

  # Read a credential WITHOUT checking purpose or destination region, for the subdomain-
  # resolution hop: that hop runs before the browser has reached the host that will establish
  # the session, so it only needs to know whose company site to look up.
  #
  # It deliberately does not consume the credential - claiming it here would break every switch.
  def peek(token)
    read(token).first
  end

  # Full check: signature, expiry, purpose, destination region. Never raises, for any input -
  # a caller that cannot get a Result back is a caller that will end up with a catch-all again.
  def verify(token, purpose:, site:)
    result, payload = read(token)
    return result unless result.ok?

    return Result.failure(:invalid) unless payload[:purpose].to_s == purpose.to_s
    return Result.failure(:wrong_region) unless payload[:site].to_s == SiteRegistry.normalize(site).to_s

    result
  end

  private

  # One place where a raw token becomes either a payload or a reason.
  #
  # MessageVerifier raises/returns the same thing for a tampered token and an expired one, but
  # `valid_message?` checks only the signature and ignores the expiry metadata. So:
  #
  #   valid_message? == false            -> the bytes were altered, or it was signed with a
  #                                         different secret  -> :invalid
  #   valid_message? == true, verified nil -> genuine, and simply timed out -> :expired
  #
  # That distinction is the whole point: :expired is worth telling a user to retry about and
  # :invalid is not, and before this they were the same message.
  def read(token)
    return [Result.failure(:missing), nil] if token.blank?
    return [Result.failure(:invalid), nil] unless @verifier.valid_message?(token)

    payload = @verifier.verified(token)
    return [Result.failure(:expired), nil] unless payload.is_a?(Hash)

    [Result.ok(email: payload[:email], origin_code: payload[:from]), payload]
  rescue StandardError => e
    # Defensive: a malformed token must never reach the caller as an exception, because the
    # caller's only safe response would be a catch-all rescue - the bug this class is fixing.
    Rails.logger.warn("[cross_site_link] unreadable credential: #{e.class}")
    [Result.failure(:invalid), nil]
  end
end
