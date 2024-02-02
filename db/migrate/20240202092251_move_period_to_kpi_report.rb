class MovePeriodToKpiReport < ActiveRecord::Migration[7.1]
  def change
    remove_column :kpis, :period, :string
    add_column :kpi_reports, :period, :string, limit: 12, default: "Quarter"
  end
end
