class ChangeDefaultForRollUpInFundFormula < ActiveRecord::Migration[8.0]
  def change
    change_column_default :fund_formulas, :roll_up, from: true, to: false
  end
end
