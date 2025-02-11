class AddTrackingGrossToCapitalDistributionPayment < ActiveRecord::Migration[7.2]
  def change
    add_column :capital_distribution_payments, :tracking_gross_payable_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_distribution_payments, :tracking_reinvestment_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0.0
    
  end
end
