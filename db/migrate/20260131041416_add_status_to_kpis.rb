class AddStatusToKpis < ActiveRecord::Migration[8.1]
  def change
    add_column :kpis, :status, :string, default: 'approved'
    add_index :kpis, :status
  end
end
