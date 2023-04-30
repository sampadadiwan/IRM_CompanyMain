class AddAmlEnabledToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :aml_enabled, :boolean, default: false
  end
end
