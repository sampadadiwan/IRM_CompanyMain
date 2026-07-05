# Returns a URL-safe token embedding actor, instance, and step position.
# No expiry — the step_position guard in the controller makes stale links safe.
class WorkflowMagicLinkGenerate < WorkflowMagicLinkAction
  step :generate

  def generate(ctx, actor_id:, instance_id:, step_position:, **)
    payload = { actor_id: actor_id, instance_id: instance_id, step_position: step_position }
    ctx[:token] = verifier.generate(payload, purpose: PURPOSE)
    true
  end
end
