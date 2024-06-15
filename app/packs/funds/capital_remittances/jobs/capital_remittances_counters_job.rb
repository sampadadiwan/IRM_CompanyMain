class CapitalRemittancesCountersJob < BulkActionJob
  def perform(user_id = nil, fund_ids)
    send_notification("Recalculating counters for Capital Remittances ....", user_id, :info) if user_id
    # We need to rollup the counters for the Capital Remittances
    # This usually takes a long time.

    # So first we will rollup the counters for the Capital Remittances for the specific funds
    CapitalRemittance.counter_culture_fix_counts where: { fund_id: fund_ids }, exclude: [:fund, %i[capital_commitment investor_kyc]]
    # Then we rollup only the fund part
    CapitalRemittance.counter_culture_fix_counts where: { id: fund_ids }, only: [:fund]
    # Then we hae to rollup the KYCs
    investor_kyc_ids = CapitalCommitment.where(fund_id: fund_ids).pluck(:investor_kyc_id).uniq
    CapitalRemittance.counter_culture_fix_counts where: { id: investor_kyc_ids }, only: [%i[capital_commitment investor_kyc]]
    send_notification("Recalculating counters completed for Capital Remittances", user_id, :success) if user_id
  end
end
