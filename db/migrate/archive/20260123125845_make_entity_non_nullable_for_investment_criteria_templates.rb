class MakeEntityNonNullableForInvestmentCriteriaTemplates < ActiveRecord::Migration[8.1]
  def change
    change_column_null :investment_criteria_templates, :entity_id, false

    add_index :investment_criteria_templates, [:entity_id, :usage_count],
              name: 'index_investment_criteria_templates_on_entity_and_usage'
  end
end
