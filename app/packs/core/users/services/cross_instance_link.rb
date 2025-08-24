# app/services/cross_instance_link.rb
class CrossInstanceLink
  class VerificationError < StandardError; end

  def initialize(secret: Rails.application.credentials["CROSS_INSTANCE_SECRET"])
    @verifier = ActiveSupport::MessageVerifier.new(secret, digest: "SHA256")
  end

  # Generate a link-safe token
  # Example: CrossInstanceLink.new.generate(user.email, "login", expires_in: 5.minutes)
  def generate(email, purpose:, expires_in: 5.minutes)
    payload = {
      email: email,
      purpose: purpose
    }
    @verifier.generate(payload, expires_in: expires_in)
  end

  # Verify token and return payload
  # Example: CrossInstanceLink.new.verify(token, purpose: "login")
  def verify(token, purpose:)
    payload = @verifier.verify(token)

    raise VerificationError, "Invalid purpose" unless payload[:purpose] == purpose

    payload # { "email" => ..., "purpose" => ... }
  rescue StandardError => e
    raise VerificationError, e.message
  end
end
