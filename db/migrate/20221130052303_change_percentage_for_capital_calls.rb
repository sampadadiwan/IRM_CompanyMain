class ChangePercentageForCapitalCalls < ActiveRecord::Migration[7.0]
  def change
    change_column :capital_commitments, :percentage, :decimal, precision: 7, scale: 4, default: "0.0"
  end
end
