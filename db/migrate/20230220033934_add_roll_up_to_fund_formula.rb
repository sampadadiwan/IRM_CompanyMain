class AddRollUpToFundFormula < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_formulas, :roll_up, :boolean, default: true
  end
end
