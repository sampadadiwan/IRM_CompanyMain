class AddAdjustmentToCapitalRemittance < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_remittances, :arrear_folio_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_remittances, :arrear_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_remittances, :net_collected_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_remittances, :net_folio_collected_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0

    # Update existing data
    CapitalRemittance.update_all("net_collected_amount_cents=collected_amount_cents")
    CapitalRemittance.update_all("net_folio_collected_amount_cents=folio_collected_amount_cents")
  end
end
