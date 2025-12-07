class AddDeletedAtToKpi < ActiveRecord::Migration[8.0]
  def change
    add_column :kpis, :deleted_at, :datetime
    add_index :kpis, :deleted_at
  end
end
