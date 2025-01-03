class AddFeesToCapitalDistributionPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :capital_distribution_payments, :fee_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_distribution_payments, :total_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
