class ApprovalGenerateNotificationsJob < ApplicationJob
  queue_as :default

  def perform(approval_id, reminder: false)
    Chewy.strategy(:active_job) do
      approval = Approval.find(approval_id)
      approval.send_notification(reminder:)
    end
  end
end
