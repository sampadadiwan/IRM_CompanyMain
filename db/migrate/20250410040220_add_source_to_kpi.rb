class AddSourceToKpi < ActiveRecord::Migration[8.0]
  def change
    add_column :kpis, :source, :string, limit: 100
  end
end
