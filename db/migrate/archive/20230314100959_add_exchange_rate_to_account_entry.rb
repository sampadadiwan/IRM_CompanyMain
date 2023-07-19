class AddExchangeRateToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_reference :account_entries, :exchange_rate, null: true, foreign_key: true
    add_reference :commitment_adjustments, :exchange_rate, null: true, foreign_key: true
    add_reference :capital_distribution_payments, :exchange_rate, null: true, foreign_key: true
    add_reference :capital_remittance_payments, :exchange_rate, null: true, foreign_key: true
    add_reference :capital_remittances, :exchange_rate, null: true, foreign_key: true
    add_reference :capital_commitments, :exchange_rate, null: true, foreign_key: true
  end
end
