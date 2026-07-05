# Returns the payload hash (with string keys via with_indifferent_access) or nil on tampering.
class WorkflowMagicLinkVerify < WorkflowMagicLinkAction
  step :verify

  def verify(ctx, token:, **)
    raw = verifier.verify(token, purpose: PURPOSE)
    ctx[:payload] = raw.with_indifferent_access
    true
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageVerifier::ExpiredSignature,
         ActiveSupport::MessageVerifier::InvalidMessage
    ctx[:payload] = nil
    true
  end
end
