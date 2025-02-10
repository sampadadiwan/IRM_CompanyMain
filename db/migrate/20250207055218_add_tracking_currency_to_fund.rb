class AddTrackingCurrencyToFund < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :tracking_currency, :string, limit: 3
    add_column :account_entries, :tracking_amount_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
