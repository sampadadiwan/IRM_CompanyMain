class AddUnitsToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :unit_types, :string, limit: 50
    add_column :funds, :units_allocation_engine, :string, limit: 50
    add_column :capital_commitments, :unit_type, :string, limit: 10
    add_column :capital_calls, :unit_prices, :text
    add_column :capital_distributions, :unit_prices, :text
  end
end
