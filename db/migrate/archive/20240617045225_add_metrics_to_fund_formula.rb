class AddMetricsToFundFormula < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_formulas, :execution_time, :integer
  end
end
