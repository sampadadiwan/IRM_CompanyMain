class ChangeFundFormualType < ActiveRecord::Migration[7.0]
  def change
    change_column :fund_formulas, :rule_type, :string, limit: 30
  end
end
