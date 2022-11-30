class CapitalCallJob < ApplicationJob
  queue_as :default

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_call_id, type = "Generate")
    Chewy.strategy(:sidekiq) do
      case type
      when "Generate"
        generate(capital_call_id)
      when "Notify"
        notify(capital_call_id)
      end
    end
  end

  def generate(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.fund.capital_commitments.each do |cc|
      # Check if we alread have a CapitalRemittance for this commitment
      cr = CapitalRemittance.where(capital_call_id: @capital_call.id, investor_id: cc.investor.id).first
      if cr
        logger.debug "CapitalCallJob: Skipping as CapitalRemittance exists for #{cc.investor.investor_name} for #{@capital_call.name}"
      else
        logger.debug "CapitalCallJob: Creating CapitalRemittance for #{cc.investor.investor_name} for #{@capital_call.name}"
        # Note the due amount for the call is calculated automatically inside CapitalRemittance
        CapitalRemittance.create(capital_call: @capital_call, fund: @capital_call.fund,
                                 entity: @capital_call.entity, investor: cc.investor, capital_commitment: cc,
                                 status: "Pending")
      end
    end
  end

  def notify(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.capital_remittances.each do |cr|
      # Send notifications to the LPs only if the CapitalCall has been approved
      cr.send_notification if @capital_call.approved
    end
  end
end
