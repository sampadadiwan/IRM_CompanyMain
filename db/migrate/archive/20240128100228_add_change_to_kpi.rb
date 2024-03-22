class AddChangeToKpi < ActiveRecord::Migration[7.1]
  def change
    add_column :kpis, :percentage_change, :decimal, precision: 5, scale: 2, default: 0.0
  end
end
