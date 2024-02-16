class ApprovalGenerateNotificationsJob < ApplicationJob
  queue_as :default

  def perform(approval_id, reminder: false)
    approval = Approval.find(approval_id)
    approval.send_notification(reminder:)
  end
end
