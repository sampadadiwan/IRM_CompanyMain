class AddTagToKpiReport < ActiveRecord::Migration[7.1]
  def change
    add_column :kpi_reports, :tag_list, :string, limit: 100
    add_reference :kpi_reports, :owner, null: true, foreign_key: { to_table: :entities }
    add_reference :kpis, :owner, null: true, foreign_key: { to_table: :entities }
  end
end
