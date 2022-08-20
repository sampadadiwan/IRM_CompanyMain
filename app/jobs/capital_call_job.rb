class CapitalCallJob < ApplicationJob
  queue_as :default

  def perform(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.fund.capital_commitments.each do |cc|
      # Note the due amount for the call is calculated automatically inside CapitalRemittance
      CapitalRemittance.create(capital_call: @capital_call, fund: @capital_call.fund,
                                                    entity: @capital_call.entity, investor: cc.investor, capital_commitment: cc,
                                                    status: "Pending")
    end
  end
end
