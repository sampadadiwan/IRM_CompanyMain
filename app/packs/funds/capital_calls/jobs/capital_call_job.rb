class CapitalCallJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :remittances

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_call_id, type = "Generate")
    @remittances = []

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
    @capital_call.fund.capital_commitments.each_with_index do |capital_commitment, _idx|
      # Check if we alread have a CapitalRemittance for this commitment
      logger.debug "CapitalCallJob: Creating CapitalRemittance for #{capital_commitment.investor.investor_name} for #{@capital_call.name}"
      # Note the due amount for the call is calculated automatically inside CapitalRemittance
      cr = CapitalRemittance.new(capital_call: @capital_call, fund: @capital_call.fund,
                                 entity: @capital_call.entity, investor: capital_commitment.investor, capital_commitment:, folio_id: capital_commitment.folio_id,
                                 status: "Pending", verified: @capital_call.generate_remittances_verified)

      next unless cr.valid?

      cr.run_callbacks(:save) { false }
      cr.run_callbacks(:create) { false }
      @remittances << cr
    end

    # import the rows
    CapitalRemittance.import @remittances

    ###########################################
    # When the remittances are created - there is no collected amount, hence code below is not required
    ###########################################

    # @capital_call.reload
    # # Ensure the counter caches are updated
    # @capital_call.collected_amount_cents = @capital_call.capital_remittances.sum(:collected_amount_cents)
    # @capital_call.save

    # @capital_call.capital_remittances.each do |cr|
    #   cr.capital_commitment.collected_amount_cents = cr.capital_commitment.capital_remittances.sum(:collected_amount_cents)
    #   cr.capital_commitment.save
    # end
    # @capital_call.fund.collected_amount_cents = @capital_call.fund.capital_remittances.sum(:collected_amount_cents)
    # @capital_call.fund.save
  end

  def notify(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.capital_remittances.each do |cr|
      # Send notifications to the LPs only if the CapitalCall has been approved
      cr.send_notification if @capital_call.approved
    end
  end
end
