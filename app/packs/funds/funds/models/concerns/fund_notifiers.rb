module FundNotifiers
  extend ActiveSupport::Concern

  def adhoc_notification(custom_notification_id)
    FundNotificationJob.perform_later(id, custom_notification_id)
  end
end
