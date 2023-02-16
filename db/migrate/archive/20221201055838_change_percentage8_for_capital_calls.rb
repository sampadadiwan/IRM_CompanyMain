class ChangePercentage8ForCapitalCalls < ActiveRecord::Migration[7.0]
  def change
    change_column :capital_commitments, :percentage, :decimal, precision: 11, scale: 8, default: "0.0"
  end
end
