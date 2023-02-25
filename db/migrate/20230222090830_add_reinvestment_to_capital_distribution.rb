class AddReinvestmentToCapitalDistribution < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_distributions, :reinvestment_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
