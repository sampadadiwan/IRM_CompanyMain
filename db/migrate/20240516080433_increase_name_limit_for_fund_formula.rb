class IncreaseNameLimitForFundFormula < ActiveRecord::Migration[7.1]
  def change
    change_column :account_entries, :name, :string, limit: 125
    change_column :fund_formulas, :name, :string, limit: 125
  end
end
