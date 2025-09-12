class AddTimingToFundFormula < ActiveRecord::Migration[8.0]
  def change
    add_column :fund_formulas, :timing, :json
  end
end
