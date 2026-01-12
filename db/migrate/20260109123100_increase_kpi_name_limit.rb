class IncreaseKpiNameLimit < ActiveRecord::Migration[8.0]
  def change
    change_column :kpis, :name, :string, limit: 100
  end
end
