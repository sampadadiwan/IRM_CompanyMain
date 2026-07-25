class AddTrackingFeeAmountsToCapitalDistributionPayments < ActiveRecord::Migration[7.2]
  def change
    # Tracking currency equivalents of the with-fees amounts, populated by TrackingCurrencyJob
    # using the exchange rate on the payment_date (same as tracking_net_payable_cents).
    add_column :capital_distribution_payments, :tracking_income_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_distribution_payments, :tracking_expense_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_distribution_payments, :tracking_tax_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_distribution_payments, :tracking_display_only_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0.0
  end
end
