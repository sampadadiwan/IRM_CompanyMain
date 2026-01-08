class IncreaseReportedKpiNameLimit < ActiveRecord::Migration[8.0]
  def change
    change_column :investor_kpi_mappings, :reported_kpi_name, :string, limit: 100
    change_column :investor_kpi_mappings, :standard_kpi_name, :string, limit: 100
  end
end
