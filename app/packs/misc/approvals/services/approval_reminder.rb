class ApprovalReminder < ApprovalService
  step :reset_notification_sent
  step :notify

  def reset_notification_sent(ctx, approval:, **)
    ctx[:reminder] = true
    approval.approval_responses.pending.update_all(notification_sent: false)
  end
end
