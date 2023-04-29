class AddActiveToFundFormula < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_formulas, :enabled, :boolean, default: false
  end
end
