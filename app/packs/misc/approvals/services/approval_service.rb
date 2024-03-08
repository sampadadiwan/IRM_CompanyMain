class ApprovalService < Trailblazer::Operation
  def handle_errors(ctx, approval:, **)
    unless approval.valid?
      ctx[:errors] = approval.errors.full_messages.join(", ")
      Rails.logger.error approval.errors.full_messages
    end
    approval.valid?
  end

  def notify(ctx, approval:, **)
    reminder = ctx[:reminder]
    ApprovalGenerateNotificationsJob.perform_later(approval.id, reminder:) if approval.approved
    true
  end
end
