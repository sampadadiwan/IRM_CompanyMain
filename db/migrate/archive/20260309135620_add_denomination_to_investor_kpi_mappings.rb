class AddDenominationToInvestorKpiMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :investor_kpi_mappings, :denomination, :string, limit: 20
  end
end
