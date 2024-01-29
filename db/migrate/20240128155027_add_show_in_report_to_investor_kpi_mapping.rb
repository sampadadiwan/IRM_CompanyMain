class AddShowInReportToInvestorKpiMapping < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kpi_mappings, :show_in_report, :boolean, default: false
  end
end
