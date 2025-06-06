class CapitalCallJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :remittances, :payments

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_call_id, type)
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

    # Some calls are for specific fund closes - so only generate remittances for the commitments in that close
    capital_commitments = @capital_call.applicable_to

    Rails.logger.debug { "######## applicable_to record count = #{capital_commitments.count}" }

    capital_commitments.each_with_index do |capital_commitment, _idx|
      # Check if we alread have a CapitalRemittance for this commitment
      Rails.logger.debug { "CapitalCallJob: Creating CapitalRemittance for #{capital_commitment.investor_name} for #{@capital_call.name}" }

      if CapitalRemittance.exists?(capital_call: @capital_call, capital_commitment:)
        Rails.logger.debug { "Skipping remittances for #{capital_commitment}, already present" }
      else

        # Note the due amount for the call is calculated automatically inside CapitalRemittance
        status = @capital_call.generate_remittances_verified ? "Paid" : "Pending"
        cr = CapitalRemittance.new(capital_call: @capital_call, fund: @capital_call.fund,
                                   entity: @capital_call.entity, investor: capital_commitment.investor, capital_commitment:, folio_id: capital_commitment.folio_id,
                                   created_by: "Call",
                                   status:, verified: @capital_call.generate_remittances_verified)

        cr.payment_date = @capital_call.due_date if cr.verified
        # Skip the counter culture updates to avoid deadlocks
        CapitalRemittance.skip_counter_culture_updates do
          result = CapitalRemittanceCreate.call(capital_remittance: cr)
          Rails.logger.error { "Error creating CapitalRemittance for #{capital_commitment.investor_name} id #{capital_commitment.id}, #{cr.errors.full_messages}" } if result.failure?
        end
      end
    end

    # Generate any payments for the imported remittances if required
    generate_remittance_payments

    # Fix the counters
    CapitalRemittancesCountersJob.perform_later([@capital_call.fund_id], nil)
  end

  def generate_remittance_payments
    # Some rows will be verified but will have no payments, for these generate the payments also
    @capital_call.reload.capital_remittances.verified.each do |cr|
      next unless cr.collected_amount_cents.zero?

      # skip the counter culture updates to avoid deadlocks
      CapitalRemittancePayment.skip_counter_culture_updates do
        crp = CapitalRemittancePayment.new(capital_remittance: cr, fund_id: cr.fund_id, entity_id: cr.entity_id, amount_cents: cr.call_amount_cents, folio_amount_cents: cr.folio_call_amount_cents, payment_date: @capital_call.due_date)

        result = CapitalRemittancePaymentCreate.call(capital_remittance_payment: crp)
        Rails.logger.error { "Error creating CapitalRemittancePayment for CapitalRemitttance - Investor #{cr.investor_name} - Commitment id #{cr.capital_commitment_id}, #{cr.errors.full_messages}" } if result.failure?
      end
    end

    # Fix the counters
    CapitalRemittancePayment.counter_culture_fix_counts where: { fund_id: @capital_call.fund_id }

    # We also need to fix the status of the CapitalRemittances, as the payments will have been created
    @capital_call.capital_remittances.each do |capital_remittance|
      CapitalRemittanceUpdate.call(capital_remittance:)
    end
  end

  def notify(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.capital_remittances.each do |cr|
      # Send notifications to the LPs only if the CapitalCall has been approved
      cr.send_notification if @capital_call.approved && @capital_call.send_call_notice_flag
    end
  end
end
