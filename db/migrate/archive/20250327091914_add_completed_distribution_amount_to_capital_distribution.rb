class AddCompletedDistributionAmountToCapitalDistribution < ActiveRecord::Migration[8.0]
  def change
    add_column :capital_distributions, :completed_distribution_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
  end
end
