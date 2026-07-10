class DocShareTokenService
  # SECURITY (finding M2): a document share link is an unauthenticated bearer token —
  # DocSharesController#view serves the document to anyone holding the URL. Give it a bounded
  # lifetime so a leaked/forwarded link cannot be replayed indefinitely. verify_token already
  # rescues ExpiredSignature → nil, so an expired link renders "Not Found".
  DEFAULT_TTL = 30.days

  def initialize(purpose: 'doc_share_token')
    @verifier = ActiveSupport::MessageVerifier.new(Rails.application.credentials["SECRET_KEY_BASE"], digest: 'SHA256')
    @purpose = purpose
  end

  def generate_token(doc_share_id, expires_in: DEFAULT_TTL)
    @verifier.generate(doc_share_id, purpose: @purpose, expires_in: expires_in)
  end

  def verify_token(token)
    @verifier.verify(token, purpose: @purpose)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageVerifier::ExpiredSignature
    nil # Return nil for invalid or expired tokens
  end
end
