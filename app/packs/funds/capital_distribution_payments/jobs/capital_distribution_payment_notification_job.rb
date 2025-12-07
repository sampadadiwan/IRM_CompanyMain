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

    Chewy.strategy(:sidekiq) do
      @capital_distribution.capital_distribution_payments.each do |cdp|
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
