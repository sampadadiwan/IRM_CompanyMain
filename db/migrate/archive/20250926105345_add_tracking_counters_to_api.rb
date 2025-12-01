class AddTrackingCountersToApi < ActiveRecord::Migration[8.0]
  def change
    add_column :aggregate_portfolio_investments, :tracking_fmv_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
    add_column :aggregate_portfolio_investments, :tracking_bought_amount_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
    add_column :aggregate_portfolio_investments, :tracking_sold_amount_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
  end
end
