class AddPropertiesToValuation < ActiveRecord::Migration[7.0]
  def change
    add_column :valuations, :net_valuation_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :valuations, :properties, :text
    add_column :entities, :valuation_math, :text
    rename_column :valuations, :pre_money_valuation_cents, :valuation_cents
  end
end
