module FundNotifiers
  extend ActiveSupport::Concern

  # investor_kyc_ids is only meaningful when the CustomNotification's email_method is
  # "adhoc_kyc_notification" — FundNotificationJob ignores it otherwise, exactly like it
  # ignores commitment_ids in that mode.
  def adhoc_notification(custom_notification_id, commitment_ids: nil, investor_kyc_ids: nil)
    FundNotificationJob.perform_later(id, custom_notification_id, commitment_ids, investor_kyc_ids)
  end
end
