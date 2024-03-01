class ApprovalService < Trailblazer::Operation
  def handle_errors(ctx, approval:, **)
    ctx[:errors] = approval.errors.full_messages unless approval.valid?
    approval.valid?
  end

  def notify(ctx, approval:, **)
    reminder = ctx[:reminder]
    ApprovalGenerateNotificationsJob.perform_later(approval.id, reminder:) if approval.approved
    true
  end
end
