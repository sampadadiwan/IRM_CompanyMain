class AddAnalysisToKpiReport < ActiveRecord::Migration[8.0]
  def change
    add_column :kpi_reports, :analysis, :text
  end
end
