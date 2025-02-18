class AddYtdToFundFormula < ActiveRecord::Migration[7.2]
  def change
    add_column :fund_formulas, :generate_ytd_qtly, :boolean, default: false
  end
end
