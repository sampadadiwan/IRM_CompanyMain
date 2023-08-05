class AddCapitalFeeToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :capital_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :funds, :other_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_calls, :capital_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_calls, :other_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0
    remove_column :capital_calls, :fee_cents
  end
end
