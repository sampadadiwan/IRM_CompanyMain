class AddExplainToFundFormula < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_formulas, :explain, :boolean, default: true
  end
end
