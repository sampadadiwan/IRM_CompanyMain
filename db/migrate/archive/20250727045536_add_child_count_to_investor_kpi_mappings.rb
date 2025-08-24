class AddChildCountToInvestorKpiMappings < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :child_count, :integer, default: 0
  end
end
