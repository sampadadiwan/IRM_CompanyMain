class AddDeletedAtToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :deleted_at, :datetime
    add_index :entity_settings, :deleted_at
  end
end
