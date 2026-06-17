module FundNotifiers
  extend ActiveSupport::Concern

  def adhoc_notification(custom_notification_id, commitment_ids: nil)
    FundNotificationJob.perform_later(id, custom_notification_id, commitment_ids)
  end
end
