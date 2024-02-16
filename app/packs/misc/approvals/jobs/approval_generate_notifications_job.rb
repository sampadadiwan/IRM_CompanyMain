class ApprovalGenerateNotificationsJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    approval = Approval.find(approval_id)
    approval.send_notification
  end
end
