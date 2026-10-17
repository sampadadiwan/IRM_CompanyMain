# Every 15 minutes (sidekiq-cron): asks Expo whether Apple/Google accepted the pushes sent at
# least 15 minutes ago, marks phones whose address has died (app uninstalled or reinstalled) so
# they are not pushed again (lp-mobile-app X10), and purges delivery rows older than 90 days.
#
# A sweep rather than a per-push scheduled job: nothing is lost if a worker restarts between a
# push and its receipt, and there is no delayed job to schedule from inside a delivery.
class ExpoPushReceiptsJob < ApplicationJob
  queue_as :low
  retry_on ExpoPushClient::TransientError, wait: :polynomially_longer, attempts: 3

  # Expo keeps receipts for a day; anything older can no longer be checked
  RECEIPT_WINDOW = 15.minutes..1.day
  RETENTION = 90.days
  BATCH = 300

  def perform
    return unless ExpoPushClient.configured?

    check_receipts
    MobilePushDelivery.where(created_at: ...RETENTION.ago).in_batches(of: 1000).delete_all
  end

  private

  def check_receipts
    due = MobilePushDelivery.where(status: "sent").where.not(ticket_id: nil)
                            .where(created_at: (RECEIPT_WINDOW.last.ago)..(RECEIPT_WINDOW.first.ago))
    due.includes(:mobile_device).find_in_batches(batch_size: BATCH) do |deliveries|
      receipts = ExpoPushClient.new.receipts(deliveries.map(&:ticket_id))
      deliveries.each { |delivery| apply(delivery, receipts[delivery.ticket_id]) }
    end
  end

  def apply(delivery, receipt)
    return if receipt.nil? # not ready yet; the next sweep looks again

    if receipt["status"] == "ok"
      delivery.update!(status: "delivered")
    else
      error = receipt.dig("details", "error") || receipt["message"]
      delivery.update!(status: "failed", error: error.to_s.truncate(255))
      delivery.mobile_device.mark_not_registered! if error == "DeviceNotRegistered"
    end
  end
end
