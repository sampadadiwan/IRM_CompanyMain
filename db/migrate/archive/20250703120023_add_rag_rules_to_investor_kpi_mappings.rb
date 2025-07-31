class AddRagRulesToInvestorKpiMappings < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :rag_rules, :json
  end
end
