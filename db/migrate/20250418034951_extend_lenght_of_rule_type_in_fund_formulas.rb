class ExtendLenghtOfRuleTypeInFundFormulas < ActiveRecord::Migration[8.0]
  def change
    change_column :fund_formulas, :rule_type, :string, limit: 50
  end
end
