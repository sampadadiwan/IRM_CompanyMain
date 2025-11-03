class AddCumulateToInvestorKpiMapping < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :cumulate, :boolean, default: false
    InvestorKpiMapping.update_all(cumulate: false)
  end
end
