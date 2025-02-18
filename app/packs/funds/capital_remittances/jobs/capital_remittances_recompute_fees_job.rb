class CapitalRemittancesRecomputeFeesJob < BulkActionJob
  def perform(capital_call_id, user_id = nil)
    send_notification("Recomputing fees for all capital remittances for capital call #{@capital_call}", user_id, :info)

    @error_msg = []
    @capital_call = CapitalCall.find(capital_call_id)
    processed_count = 0
    Chewy.strategy(:sidekiq) do
      @capital_call.capital_remittances.each do |capital_remittance|
        CapitalRemittanceUpdate.call(capital_remittance:)
        processed_count += 1
      rescue StandardError => e
        msg = "Error recomputing fees for capital remittance #{capital_remittance.id}: #{e.message}"
        send_notification(msg, user_id, :danger)
        @error_msg << { msg:, folio_id: capital_remittance.folio_id, capital_remittance_id: capital_remittance.id, for: capital_remittance.capital_call }
      end
    end

    if @error_msg.present?
      msg = "Recompute completed for #{processed_count} records, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      send_notification("Recomputed fees for all capital remittances successfully for capital call #{@capital_call}", user_id, :info)
    end
  end
end
