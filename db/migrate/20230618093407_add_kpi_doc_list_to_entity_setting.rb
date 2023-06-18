class AddKpiDocListToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :kpi_doc_list, :string
  end
end
