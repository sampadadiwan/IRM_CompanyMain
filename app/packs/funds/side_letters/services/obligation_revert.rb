# Undoes a wrongly applied waive/expire/dispute: the obligation returns to
# active and its projections are rebuilt (recurring → a fresh TaskRecurrenceRule
# from the stored RRULE; dated one-off → a new task unless one already exists).
# Fulfillment history was never touched by the teardown, so nothing to restore.
class ObligationRevert < Trailblazer::Operation
  REVERTIBLE_STATUSES = %w[waived expired disputed].freeze

  step :validate
  step :reactivate
  step :reproject
  left :handle_errors

  def validate(ctx, obligation:, **)
    return true if obligation.approved? && REVERTIBLE_STATUSES.include?(obligation.status.to_s)

    ctx[:error] = "Only waived, expired, or disputed obligations can be reverted"
    false
  end

  def reactivate(_ctx, obligation:, **)
    obligation.update!(status: "active")
  end

  def reproject(ctx, obligation:, **)
    result = ObligationProjection.call(obligation: obligation)
    ctx[:error] = result[:error] if result.failure?
    result.success?
  end

  def handle_errors(ctx, **)
    Rails.logger.warn("[ObligationRevert] #{ctx[:error]}")
    false
  end
end
