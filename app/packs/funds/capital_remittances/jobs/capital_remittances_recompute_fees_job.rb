class CapitalRemittancesRecomputeFeesJob < BulkActionJob
  def perform(capital_call_id, user_id = nil)
    send_notification("Recomputing fees for all capital remittances for capital call #{@capital_call}", user_id, :info)

    @capital_call = CapitalCall.find(capital_call_id)
    Chewy.strategy(:sidekiq) do
      @capital_call.capital_remittances.each do |capital_remittance|
        CapitalRemittanceUpdate.wtf?(capital_remittance:)
      end
    end

    send_notification("Recomputed fees for all capital remittances successfully for capital call #{@capital_call}", user_id, :info)
  end
end
