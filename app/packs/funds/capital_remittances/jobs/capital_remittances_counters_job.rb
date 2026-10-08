class CapitalRemittancesCountersJob < BulkActionJob
  queue_as :serial

  # capital_call_id is optional: CapitalCallJob passes it so the call's open pages can be refreshed
  # once the counters are right. Imports leave it out, and a job enqueued before it existed arrives
  # with two arguments.
  def perform(fund_ids, user_id = nil, capital_call_id = nil)
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

    # We need to change the status to "Paid" for the Capital Remittances where the call_amount_cents = collected_amount_cents
    CapitalRemittance.where.not(status: "Paid").where(fund_id: fund_ids).where("call_amount_cents = collected_amount_cents").update_all(status: "Paid")

    # Now the call's totals are right: refresh its stats cards, and the list too, since the update_all
    # above can flip remittance statuses to Paid
    broadcast_capital_call_change(capital_call_id)

    send_notification("Recalculating counters completed for Capital Remittances", user_id, :success) if user_id
  end

  private

  # No-op without a call id, or if the call was deleted meanwhile
  def broadcast_capital_call_change(capital_call_id)
    capital_call = capital_call_id && CapitalCall.find_by(id: capital_call_id)
    return unless capital_call

    capital_call.broadcast_stats_change
    capital_call.broadcast_remittances_change
  end
end
