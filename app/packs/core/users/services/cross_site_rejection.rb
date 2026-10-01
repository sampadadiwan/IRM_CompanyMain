# frozen_string_literal: true

# The single place a failed hand-off becomes an outcome: one user-facing phrase, one log line,
# one metric, one decision about whether to offer a way back.
#
# Before this, UsersController had a bare `rescue CrossSiteLink::VerificationError` that
# rendered `plain: "Invalid or expired link"` with no log line and no navigation. Five
# different causes produced one dead page, so support could not tell a slow connection from a
# misconfigured region, and the user had nothing to click.
#
# Side-effect free: building one of these decides a message, a link and a log line, and nothing
# else. The caller emits the metric, so constructing a rejection in a test does not count a
# hand-off that never happened.
class CrossSiteRejection
  # Every reason the hand-off can end badly. CrossSiteLink owns the first four; the rest are
  # decided outside it - by Nonce, by the user lookup, and by reclassification below.
  REASONS = (CrossSiteLink::REASONS + %i[already_used no_account secret_mismatch]).freeze

  # Retrying is pointless when the regions no longer share a secret, and misleading when we
  # cannot even read the credential, so those reasons never offer a "return to" link.
  REASONS_WITHOUT_RETURN = %i[secret_mismatch missing invalid].freeze

  attr_reader :reason, :origin_code

  # `from` is the raw query parameter, deliberately unsigned - see #origin_url.
  def self.for(reason:, from: nil, email: nil)
    new(reason: reason, from: from, email: email)
  end

  def initialize(reason:, from: nil, email: nil)
    raise ArgumentError, "unknown cross-site rejection reason #{reason.inspect}" unless REASONS.include?(reason)

    @reason = reclassify(reason)
    @email = email
    @origin_code = SiteRegistry.normalize(from)
  end

  # This region's code, or nil when the registry itself is what is misconfigured. Exposed so the
  # caller can label its metric without reaching back into SiteRegistry.
  def region
    safe_current_code
  end

  # What the sign-in screen renders. A Hash, not a String, on purpose: the Devise sign-in view's
  # generic `flash.each` loop is guarded by `msg.is_a?(String)`, so a Hash entry is skipped
  # there and rendered once by the dedicated partial instead - which means the "return to" link
  # can be a real anchor without putting html_safe markup in a flash message.
  def flash_payload
    { "reason" => reason.to_s, "message" => message, "origin_url" => origin_url,
      "origin_code" => origin_code }.compact
  end

  def message
    I18n.t("cross_region.rejection.#{reason}",
           region: region_name(safe_current_code),
           default: I18n.t("cross_region.rejection.invalid", region: region_name(safe_current_code)))
  end

  # Where "return to <region>" points, or nil when there is nothing safe to point at.
  #
  # The origin travels as a plain query parameter rather than inside the signed payload,
  # because MessageVerifier will not hand back the contents of an EXPIRED credential - which is
  # exactly the case where the user most needs the link. It is safe unsigned because it is only
  # ever a lookup key into SiteRegistry: a tampered value either names another legitimately
  # configured region or resolves to nil. It is never interpolated into a URL.
  def origin_url
    return nil if REASONS_WITHOUT_RETURN.include?(reason)
    return nil if origin_code.nil? || origin_code == safe_current_code

    SiteRegistry.url_for(origin_code)
  end

  # What goes in the log. The credential itself is never here, and never anywhere else.
  def log_fields
    { reason: reason, region: safe_current_code, server: Socket.gethostname, email: @email }.compact
  end

  def to_log_line
    "cross_region_handoff rejected #{log_fields.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  private

  # A bad signature is reported as tampering UNLESS the hourly trust check has already found
  # that the two regions hold different secrets - in which case it is our configuration, not
  # the user's link, and the banner must stop inviting a retry that cannot work.
  def reclassify(reason)
    return :secret_mismatch if reason == :invalid && CrossSiteTrust.peer_mismatch?

    reason
  end

  def region_name(code)
    I18n.t("cross_region.regions.#{code}", default: code.to_s)
  end

  # A rejection must still render even if the registry is what is broken.
  def safe_current_code
    SiteRegistry.current_code
  rescue SiteRegistry::ConfigurationError
    nil
  end
end
