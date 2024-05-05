class CapitalCommitmentRemittanceJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :remittances, :payments

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_commitment_id)
    Chewy.strategy(:active_job) do
      generate_for_commitment(capital_commitment_id)
    end
  end

  def generate_for_commitment(capital_commitment_id)
    capital_commitment = CapitalCommitment.find(capital_commitment_id)
    capital_commitment.fund.capital_calls.each do |capital_call|
      # Generate the remittance only if the call is for All or this Fund Close
      next unless capital_call.applicable_to.exists?(id: capital_commitment.id)

      status = capital_call.generate_remittances_verified ? "Paid" : "Pending"
      cr = CapitalRemittance.new(capital_call:, fund: capital_call.fund,
                                 entity: capital_call.entity, investor: capital_commitment.investor,
                                 capital_commitment:, folio_id: capital_commitment.folio_id,
                                 created_by: "Call",
                                 status:, verified: capital_call.generate_remittances_verified)

      CapitalRemittanceCreate.call(capital_remittance: cr)
    end
  end
end
