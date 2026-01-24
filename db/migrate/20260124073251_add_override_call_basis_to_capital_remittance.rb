class AddOverrideCallBasisToCapitalRemittance < ActiveRecord::Migration[8.1]
  def change
    # add_column :capital_remittances, :call_basis, :string, limit: 40

    # # Backfill existing records with call_basis from associated capital calls
    # CapitalRemittance.includes(:capital_call).update_all(
    #   "call_basis = (SELECT call_basis FROM capital_calls WHERE capital_calls.id = capital_remittances.capital_call_id)"
    # )

    # # This is to fix any counter_culture discrepancies as changes made to rollup for funds
    # CapitalDistributionPayment.counter_culture_fix_counts
  end
end
