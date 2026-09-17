class CapitalDistributionDateChangeJob < BulkActionJob
  def perform(capital_distribution_id, user_id = nil)
    @capital_distribution = CapitalDistribution.find(capital_distribution_id)
    send_notification("Updating payment dates to #{I18n.l(@capital_distribution.distribution_date)} for all payments of #{@capital_distribution}", user_id, :info) if user_id.present?

    @error_msg = []
    processed_count = 0
    Chewy.strategy(:sidekiq) do
      @capital_distribution.capital_distribution_payments.find_each do |capital_distribution_payment|
        capital_distribution_payment.update!(payment_date: @capital_distribution.distribution_date)
        processed_count += 1
      rescue StandardError => e
        msg = "Error updating payment date for capital distribution payment #{capital_distribution_payment.id}: #{e.message}"
        send_notification(msg, user_id, :danger) if user_id.present?
        @error_msg << { msg:, folio_id: capital_distribution_payment.folio_id, capital_distribution_payment_id: capital_distribution_payment.id, for: capital_distribution_payment.capital_distribution }
      end
    end

    if @error_msg.present?
      msg = "Payment date update completed for #{processed_count} records, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger) if user_id.present?
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now if user_id.present?
    elsif user_id.present?
      send_notification("Updated payment dates for all payments of #{@capital_distribution}. Recomputing fees...", user_id, :info)
    end

    CapitalDistributionPaymentRecomputeFeesJob.perform_later(@capital_distribution.id, user_id)
  end
end
