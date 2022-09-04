class AddDistributionToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :distribution_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0" 
    add_column :capital_distributions, :distribution_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0" 
  end
end
