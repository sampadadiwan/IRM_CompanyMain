# The counsel review gate's "reject" transition — a rejected obligation never
# generates tasks or alerts (nothing was projected while pending, so there is
# nothing to tear down).
class ObligationReject < Trailblazer::Operation
  step :validate_pending
  step :mark_rejected
  step :refresh_side_letter
  left :handle_errors

  def validate_pending(ctx, obligation:, **)
    return true if obligation.pending_review?

    ctx[:error] = "Obligation has already been reviewed"
    false
  end

  def mark_rejected(ctx, obligation:, user: nil, **)
    obligation.update!(
      review_status: "rejected",
      reviewed_by_id: user&.id,
      reviewed_at: Time.current
    )
  end

  # Portfolio investment obligations have no side_letter — skip the refresh
  # for those; their extraction status is tracked per-agent-run, not per-document.
  def refresh_side_letter(_ctx, obligation:, **)
    obligation.side_letter&.refresh_extraction_status!
    true
  end

  def handle_errors(ctx, **)
    Rails.logger.warn("[ObligationReject] #{ctx[:error]}")
    false
  end
end
