class AddEnablePortCoToKpiReport < ActiveRecord::Migration[8.0]
  def change
    add_column :kpi_reports, :enable_portco_upload, :boolean, default: false, null: false
    KpiReport.update_all(enable_portco_upload: false)
  end
end
