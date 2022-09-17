class AddPrefConversionToAggregateInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_investments, :preferred_converted_qty, :integer, default: 0
    add_column :investments, :preferred_converted_qty, :integer, default: 0
  end
end
