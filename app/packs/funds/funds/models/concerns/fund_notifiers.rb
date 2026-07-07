module FundNotifiers
  extend ActiveSupport::Concern

  # investor_kyc_ids is only meaningful when the CustomNotification's email_method is
  # "adhoc_kyc_notification" — FundNotificationJob ignores it otherwise, exactly like it
  # ignores commitment_ids in that mode.
  #
  # triggered_by_user_id (optional) is the admin who clicked "Send Notification" — threaded
  # through to each recipient's Noticed::Event params so SkippedNotificationReportJob can email
  # them directly if attachment_mandatory causes a skip, instead of falling back to company admins.
  def adhoc_notification(custom_notification_id, commitment_ids: nil, investor_kyc_ids: nil, triggered_by_user_id: nil)
    FundNotificationJob.perform_later(id, custom_notification_id, commitment_ids, investor_kyc_ids, triggered_by_user_id)
  end
end
