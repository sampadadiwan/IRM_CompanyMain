class AddUnitsToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :units_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_distribution_payments, :units_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
