class FundNotificationJob < ApplicationJob
  queue_as :default

  def perform(fund_id, custom_notification_id, commitment_ids = nil)
    fund = Fund.find(fund_id)
    custom_notification = CustomNotification.find(custom_notification_id)

    # nil/empty means all commitments; otherwise filter to the selected subset
    commitments = commitment_ids.present? ? fund.capital_commitments.where(id: commitment_ids) : fund.capital_commitments
    commitments.find_each do |commitment|
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
