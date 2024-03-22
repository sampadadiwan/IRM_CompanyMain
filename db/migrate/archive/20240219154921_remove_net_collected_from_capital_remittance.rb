class RemoveNetCollectedFromCapitalRemittance < ActiveRecord::Migration[7.1]
  def change
    remove_column :capital_remittances, :net_collected_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    remove_column :capital_remittances, :net_folio_collected_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
  end
end
