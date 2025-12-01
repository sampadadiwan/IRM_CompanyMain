class AddCumulatedToKpiReport < ActiveRecord::Migration[8.0]
  def change
    add_column :kpi_reports, :cumulation_completed, :boolean, default: false, null: false
  end
end
