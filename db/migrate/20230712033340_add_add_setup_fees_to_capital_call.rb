class AddAddSetupFeesToCapitalCall < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_calls, :add_setup_fees, :boolean, default: false
    add_column :capital_remittances, :fee_cents, :decimal, precision: 20, scale: 2, default: 0.0 
    add_column :capital_remittances, :folio_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0 
  end
end
