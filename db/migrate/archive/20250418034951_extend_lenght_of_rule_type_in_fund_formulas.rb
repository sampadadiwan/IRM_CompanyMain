class ExtendLenghtOfRuleTypeInFundFormulas < ActiveRecord::Migration[8.0]
  def up
    change_column :fund_formulas, :rule_type, :string, limit: 50
  end

  def down
    change_column :fund_formulas, :rule_type, :string, limit: 30
  end
end
