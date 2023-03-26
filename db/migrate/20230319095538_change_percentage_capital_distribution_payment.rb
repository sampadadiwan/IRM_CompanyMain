class ChangePercentageCapitalDistributionPayment < ActiveRecord::Migration[7.0]
  def change
    change_column :capital_distribution_payments, :percentage, :decimal, precision: 12, scale: 8, default: 0
  end
end
