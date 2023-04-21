class ChangePercentagePrecisionInCapitalCall < ActiveRecord::Migration[7.0]
  def change
    change_column :capital_calls, :percentage_called, :decimal, precision: 11, scale: 8, default: 0
  end
end
