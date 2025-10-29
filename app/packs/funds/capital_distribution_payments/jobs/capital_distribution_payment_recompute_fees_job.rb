class CapitalDistributionPaymentRecomputeFeesJob < BulkActionJob
  def perform(capital_distribution_id, user_id = nil)
    send_notification("Recomputing fees for all payments for distribution #{@capital_distribution}", user_id, :info)

    @error_msg = []
    @capital_distribution = CapitalDistribution.find(capital_distribution_id)
    processed_count = 0
    Chewy.strategy(:sidekiq) do
      @capital_distribution.capital_distribution_payments.each do |capital_distribution_payment|
        CapitalDistributionPaymentUpdate.call(capital_distribution_payment:)
        processed_count += 1
      rescue StandardError => e
        msg = "Error recomputing fees for capital distribution payment #{capital_distribution_payment.id}: #{e.message}"
        send_notification(msg, user_id, :danger)
        @error_msg << { msg:, folio_id: capital_distribution_payment.folio_id, capital_distribution_payment_id: capital_distribution_payment.id, for: capital_distribution_payment.capital_distribution }
      end
    end

    if @error_msg.present?
      @main_error = "Recompute completed for #{processed_count} records, with #{@error_msg.length} errors"
      msg = "#{@main_error}. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      send_error_notifications(msg, @error_msg, user_id, :danger)
      email_errors
    else
      send_notification("Recomputed fees for all capital distribution payments successfully for distribution #{@capital_distribution}", user_id, :success)
    end
  end
end
