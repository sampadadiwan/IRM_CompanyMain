class AddTrackingCurrencyToCapitalRemittancePayment < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :tracking_collected_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :capital_commitments, :tracking_collected_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :capital_remittances, :tracking_collected_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :capital_remittance_payments, :tracking_amount_cents, :decimal, precision: 20, scale: 4, default: 0

    add_column :capital_remittances, :tracking_call_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :funds, :tracking_call_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :funds, :tracking_co_invest_call_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    
    add_column :capital_distribution_payments, :tracking_net_payable_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :funds, :tracking_distribution_amount_cents, :decimal, precision: 20, scale: 4, default: 0
    add_column :capital_commitments, :tracking_distribution_amount_cents, :decimal, precision: 20, scale: 4, default: 0
  end
end
