class FundNotificationJob < ApplicationJob
  queue_as :default

  def perform(fund_id, custom_notification_id)
    fund = Fund.find(fund_id)
    custom_notification = CustomNotification.find(custom_notification_id)

    fund.capital_commitments.find_each do |commitment|
      investor = commitment.investor
      # recipients will be the capital_commitment.investor.notification_users
      recipients = investor.notification_users(commitment)

      recipients.each do |recipient|
        FundCommitmentNotifier.with(
          record: commitment,
          entity_id: fund.entity_id,
          custom_notification_id: custom_notification.id,
          email_method: custom_notification.email_method
        ).deliver_later(recipient)
      end
    end
  end
end
