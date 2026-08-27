class CapitalCallDateChangeJob < BulkActionJob
  def perform(capital_call_id, user_id = nil)
    @capital_call = CapitalCall.find(capital_call_id)
    send_notification("Updating remittance dates to #{I18n.l(@capital_call.call_date)} for all capital remittances of #{@capital_call}", user_id, :info)

    @error_msg = []
    processed_count = 0
    Chewy.strategy(:sidekiq) do
      @capital_call.capital_remittances.find_each do |capital_remittance|
        capital_remittance.update!(remittance_date: @capital_call.call_date)
        processed_count += 1
      rescue StandardError => e
        msg = "Error updating remittance date for capital remittance #{capital_remittance.id}: #{e.message}"
        send_notification(msg, user_id, :danger)
        @error_msg << { msg:, folio_id: capital_remittance.folio_id, capital_remittance_id: capital_remittance.id, for: capital_remittance.capital_call }
      end
    end

    if @error_msg.present?
      msg = "Remittance date update completed for #{processed_count} records, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      send_notification("Updated remittance dates for all capital remittances of #{@capital_call}. Recomputing fees...", user_id, :info)
    end

    CapitalRemittancesRecomputeFeesJob.perform_later(@capital_call.id, user_id)
  end
end
