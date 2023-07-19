class AddEnableKpiToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_kpis, :boolean, default: false
  end
end
