class ChangeKpiValue < ActiveRecord::Migration[7.1]
  def change
    change_column :kpis, :value, :decimal, precision: 20, scale: 6
  end
end
