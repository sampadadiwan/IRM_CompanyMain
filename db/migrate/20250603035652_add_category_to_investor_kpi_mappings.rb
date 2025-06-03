class AddCategoryToInvestorKpiMappings < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :category, :string, limit: 40
  end
end
