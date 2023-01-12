class CapitalCallRemittanceDocJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_call_id, _user_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.capital_remittances.each do |cr|
      CapitalRemittanceDocJob.perform_later(cr.id)
    end
  end
end
