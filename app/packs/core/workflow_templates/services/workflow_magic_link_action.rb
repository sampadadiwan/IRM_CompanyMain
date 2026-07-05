class WorkflowMagicLinkAction < Trailblazer::Operation
  PURPOSE = 'workflow_magic_link'

  private

  # Reuse the same key as DocShareTokenService so we don't need a new secret
  def verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.credentials["SECRET_KEY_BASE"],
      digest: 'SHA256'
    )
  end
end
