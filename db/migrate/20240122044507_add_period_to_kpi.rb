class AddPeriodToKpi < ActiveRecord::Migration[7.1]
  def change
    add_column :kpis, :period, :string, limit: 12, default: "Quarter"
  end
end
