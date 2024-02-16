class ApprovalService < Trailblazer::Operation
  def handle_errors(ctx, approval:, **)
    ctx[:errors] = approval.errors unless approval.valid?
    approval.valid?
  end

  def notify(_ctx, approval:, **)
    ApprovalGenerateNotificationsJob.perform_later(approval.id) if approval.approved
    true
  end
end
