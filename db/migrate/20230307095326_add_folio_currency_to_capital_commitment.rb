class AddFolioCurrencyToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :folio_currency, :string, limit: 5
    add_column :capital_commitments, :folio_committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    
    add_column :capital_remittances, :folio_call_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_remittances, :folio_collected_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_remittances, :folio_committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    add_column :capital_remittance_payments, :folio_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    add_column :capital_distribution_payments, :folio_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    add_column :account_entries, :folio_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
