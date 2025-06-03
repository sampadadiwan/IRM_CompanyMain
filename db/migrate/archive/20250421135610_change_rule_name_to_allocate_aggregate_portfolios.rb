class ChangeRuleNameToAllocateAggregatePortfolios < ActiveRecord::Migration[8.0]
  def up
    FundFormula.where(rule_type: "AllocatePortfolio").update_all(rule_type: "AllocateAggregatePortfolios")
  end
end
