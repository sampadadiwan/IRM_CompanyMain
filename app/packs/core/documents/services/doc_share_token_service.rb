class DocShareTokenService
  def initialize(purpose: 'doc_share_token')
    @verifier = ActiveSupport::MessageVerifier.new(Rails.application.credentials["SECRET_KEY_BASE"], digest: 'SHA256')
    @purpose = purpose
  end

  def generate_token(doc_share_id)
    @verifier.generate(doc_share_id, purpose: @purpose)
  end

  def verify_token(token)
    @verifier.verify(token, purpose: @purpose)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageVerifier::ExpiredSignature
    nil # Return nil for invalid or expired tokens
  end
end
