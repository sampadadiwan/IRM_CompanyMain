class AddDeletedAtToKpiReport < ActiveRecord::Migration[7.2]
  def change
    add_column :kpi_reports, :deleted_at, :datetime
    add_index :kpi_reports, :deleted_at
  end
end
