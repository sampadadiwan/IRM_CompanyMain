# The counsel review gate's "approve" transition. Only here do obligations
# become active and project tasks — extraction can never do this directly.
class ObligationApprove < Trailblazer::Operation
  step :validate_pending
  step :ensure_owner
  step :mark_approved
  step :project
  step :refresh_side_letter
  left :handle_errors

  def validate_pending(ctx, obligation:, **)
    return true if obligation.pending_review?

    ctx[:error] = "Obligation has already been reviewed"
    false
  end

  # Someone must be on the hook before an obligation can go live
  def ensure_owner(ctx, obligation:, **)
    return true if obligation.owner_present?

    ctx[:error] = "An owner (user or team) is required before approval"
    false
  end

  def mark_approved(ctx, obligation:, user: nil, **)
    obligation.update!(
      review_status: "approved",
      status: "active",
      reviewed_by_id: user&.id,
      reviewed_at: Time.current,
      delta: false
    )
  end

  def project(ctx, obligation:, **)
    result = ObligationProjection.call(obligation: obligation)
    ctx[:error] = result[:error] if result.failure?
    result.success?
  end

  # Once nothing is left pending on the side letter, mark it counsel_reviewed
  def refresh_side_letter(_ctx, obligation:, **)
    obligation.side_letter.refresh_extraction_status!
    true
  end

  def handle_errors(ctx, **)
    Rails.logger.warn("[ObligationApprove] #{ctx[:error]}")
    false
  end
end
