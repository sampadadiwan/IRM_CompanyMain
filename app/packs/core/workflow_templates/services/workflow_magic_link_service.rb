class WorkflowMagicLinkService
  PURPOSE = 'workflow_magic_link'

  def initialize
    # Reuse the same key as DocShareTokenService so we don't need a new secret
    @verifier = ActiveSupport::MessageVerifier.new(
      Rails.application.credentials["SECRET_KEY_BASE"],
      digest: 'SHA256'
    )
  end

  # Returns a URL-safe token embedding actor, instance, and step position.
  # No expiry — the step_position guard in the controller makes stale links safe.
  def generate_token(actor_id:, instance_id:, step_position:)
    payload = { actor_id: actor_id, instance_id: instance_id, step_position: step_position }
    @verifier.generate(payload, purpose: PURPOSE)
  end

  # Returns the payload hash (with string keys via with_indifferent_access) or nil on tampering.
  def verify_token(token)
    raw = @verifier.verify(token, purpose: PURPOSE)
    raw.with_indifferent_access
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageVerifier::ExpiredSignature,
         ActiveSupport::MessageVerifier::InvalidMessage
    nil
  end
end
