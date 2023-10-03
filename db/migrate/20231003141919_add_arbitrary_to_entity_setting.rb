class AddArbitraryToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :arbitrary, :string, limit: 20
  end
end
