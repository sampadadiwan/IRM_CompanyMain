class CapitalDistributionPaymentNotificationJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial

  def perform(capital_distribution_id, user_id)
    @capital_distribution_id = capital_distribution_id
    @capital_distribution = CapitalDistribution.find(capital_distribution_id)
    @fund = @capital_distribution.fund
    @user_id = user_id

    success = 0
    failure = 0
    @error_msg = {}

    payments = @capital_distribution.capital_distribution_payments.includes(:fund, { investor: :approved_users }, :capital_commitment)

    # Nothing would be sent at all under these conditions (see
    # CapitalDistributionPayment#send_notification), so there is nothing to preflight and no
    # reason to alert anyone.
    distribution_sends = @capital_distribution.send_notification_on_complete && @capital_distribution.approved &&
                         !@capital_distribution.manual_generation

    # Size-check every payment's attachments before sending any of them, so an oversized
    # document stops the whole distribution run instead of bouncing investor by investor.
    # Scoped to the payments this run would actually email — an oversized document on one
    # already notified (or not yet completed) must not block the rest of the distribution.
    # Returns rather than raises — a raise would just have Sidekiq retry the same batch.
    blocked = distribution_sends && NotificationAttachmentPreflight.batch_error_message(
      payments.where(completed: true, notification_sent: [false, nil]),
      @capital_distribution.custom_notification(:send_notification),
      context: "Cannot send distribution notices for #{@capital_distribution}",
      skip_if: ->(cdp) { cdp.capital_commitment.skip_doc_gen? }
    ) { |cdp| NotificationAttachmentPreflight.auto_attached_documents(cdp) }
    if blocked.present?
      # report_blocked_send broadcasts the UserAlert itself now.
      NotificationAttachmentPreflight.report_blocked_send(blocked, entity_id: @capital_distribution.entity_id, user_id:,
                                                                   subject: "Distribution notices not sent")
      return
    end

    Chewy.strategy(:sidekiq) do
      payments.find_each do |cdp|
        result = CapitalDistributionPaymentSendNotification.call(capital_distribution_payment: cdp, force_notification: false)
        success += 1 if result.success?
        failure += 1 unless result.success?
        @error_msg["Investor: #{cdp.investor_name}"] = result[:notification_message] unless result.success?
      end

      sleep(2)
      msg = "Capital Distribution Payment Notification Job completed for Distribution: #{@capital_distribution}. Success: #{success} payments, Failure: #{failure} payments."
      send_notification(msg, user_id)
      send_errors_notification(msg, @error_msg, user_id) if failure.positive?
      @main_error = "Distribution payment notifications completed with #{@error_msg.length} errors."
      email_errors if failure.positive?
    end
  end
end
