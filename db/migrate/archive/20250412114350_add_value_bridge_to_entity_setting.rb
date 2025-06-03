class AddValueBridgeToEntitySetting < ActiveRecord::Migration[8.0]
  def change
    add_column :entity_settings, :value_bridge_cols, :string
  end
end
