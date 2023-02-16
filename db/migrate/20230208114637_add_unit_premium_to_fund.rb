class AddUnitPremiumToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :total_units_premium_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
