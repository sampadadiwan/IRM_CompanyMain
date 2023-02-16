class AddRuleTypeToFundRule < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_formulas, :rule_type, :string, limit: 10
  end
end
