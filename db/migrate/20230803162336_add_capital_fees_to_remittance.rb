class AddCapitalFeesToRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :capital_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0 
    add_column :capital_remittances, :other_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_remittances, :folio_capital_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0 
    add_column :capital_remittances, :folio_other_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0 
    remove_column :capital_remittances, :fee_cents
    remove_column :capital_remittances, :folio_fee_cents
    remove_column :capital_calls, :add_fees
  end
end
