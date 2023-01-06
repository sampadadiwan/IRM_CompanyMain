class CapitalCallJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :remittances, :payments

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_call_id, type = "Generate")
    @remittances = []
    @payments = []
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
      Rails.logger.debug { "CapitalCallJob: Creating CapitalRemittance for #{capital_commitment.investor.investor_name} for #{@capital_call.name}" }

      # Note the due amount for the call is calculated automatically inside CapitalRemittance
      status = @capital_call.generate_remittances_verified ? "Paid" : "Pending"
      cr = CapitalRemittance.new(capital_call: @capital_call, fund: @capital_call.fund,
                                 entity: @capital_call.entity, investor: capital_commitment.investor, capital_commitment:, folio_id: capital_commitment.folio_id,
                                 status:, verified: @capital_call.generate_remittances_verified)

      cr.run_callbacks(:save) { false }
      cr.run_callbacks(:create) { false }
      @remittances << cr if cr.valid?
    end

    # import the rows
    CapitalRemittance.import @remittances

    # Some rows will be verified but will have no payments, for these generate the payments also
    @capital_call.capital_remittances.verified.each do |cr|
      next unless cr.collected_amount_cents.zero?

      crp = CapitalRemittancePayment.new(capital_remittance: cr, fund_id: cr.fund_id, entity_id: cr.entity_id, amount_cents: cr.call_amount_cents, payment_date: Time.zone.today)

      crp.run_callbacks(:save) { false }
      crp.run_callbacks(:create) { false }
      @payments << crp if crp.valid?
    end

    CapitalRemittancePayment.import @payments
    CapitalRemittancePayment.counter_culture_fix_counts only: :capital_remittance, where: { fund_id: @capital_call.fund_id }

    # Update the search index
    CapitalRemittanceIndex.import(@capital_call.capital_remittances)
    # Update the counter caches
    CapitalRemittance.counter_culture_fix_counts only: :capital_call, where: { id: @capital_call.id }
    CapitalRemittance.counter_culture_fix_counts only: :capital_commitment, where: { fund_id: @capital_call.fund_id }
    CapitalRemittance.counter_culture_fix_counts only: :fund, where: { id: @capital_call.fund_id }

    # Mark all remittances for this call as paid if the called - collected < 100 cents
    CapitalRemittance.where(capital_call_id: @capital_call.id).where("ABS(capital_remittances.collected_amount_cents - capital_remittances.call_amount_cents) <= 100").update_all(status: "Paid")
  end

  def notify(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.capital_remittances.each do |cr|
      # Send notifications to the LPs only if the CapitalCall has been approved
      cr.send_notification if @capital_call.approved
    end
  end
end
