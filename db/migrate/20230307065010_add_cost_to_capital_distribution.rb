class AddCostToCapitalDistribution < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_distributions, :cost_of_investment_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_distribution_payments, :cost_of_investment_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
