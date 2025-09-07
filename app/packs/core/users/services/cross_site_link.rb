# app/services/cross_site_link.rb
class CrossSiteLink
  class VerificationError < StandardError; end

  def initialize(secret: Rails.application.credentials["CROSS_INSTANCE_SECRET"])
    @verifier = ActiveSupport::MessageVerifier.new(secret, digest: "SHA256")
  end

  # Generate a link-safe token
  # Example: CrossSiteLink.new.generate(user.email, "login", expires_in: 5.minutes)
  def generate(email, purpose:, site:, expires_in: 5.minutes)
    payload = {
      email: email,
      purpose: purpose,
      site: site
    }
    @verifier.generate(payload, expires_in: expires_in)
  end

  # Verify token and return payload
  # Example: CrossSiteLink.new.verify(token, purpose: "login")
  def verify(token, purpose:, site:)
    payload = @verifier.verify(token)

    raise VerificationError, "Invalid purpose" unless payload[:purpose] == purpose
    raise VerificationError, "Invalid site" unless payload[:site] == site

    payload # { "email" => ..., "purpose" => ... }
  rescue StandardError => e
    raise VerificationError, e.message
  end
end
