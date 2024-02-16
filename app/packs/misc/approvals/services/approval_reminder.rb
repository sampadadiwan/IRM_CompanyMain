class ApprovalReminder < ApprovalService
  step :reset_notification_sent
  step :notify

  def reset_notification_sent(_ctx, approval:, **)
    approval.approval_responses.pending.update_all(notification_sent: false)
  end
end
