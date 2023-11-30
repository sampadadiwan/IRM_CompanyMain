class AddRuleTypeToFundFormula < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_formulas, :rule_for, :string, limit: 10, default: "Accounting"
    add_column :allocation_runs, :rule_for, :string, limit: 10, default: "Accounting"
  end
end
