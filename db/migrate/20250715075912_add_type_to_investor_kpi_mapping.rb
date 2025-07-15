class AddTypeToInvestorKpiMapping < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :data_type, :string, limit: 10, default: 'numeric'
  end
end
