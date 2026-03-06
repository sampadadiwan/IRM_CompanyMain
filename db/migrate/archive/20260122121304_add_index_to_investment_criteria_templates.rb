class AddIndexToInvestmentCriteriaTemplates < ActiveRecord::Migration[8.1]
  def change
    add_index :investment_criteria_templates, [:created_by_user_id, :usage_count], 
              name: 'index_investment_criteria_templates_on_user_and_usage'
  end
end
