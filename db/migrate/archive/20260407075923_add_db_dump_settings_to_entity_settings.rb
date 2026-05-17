class AddDbDumpSettingsToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :db_dumps_enable, :boolean, default: false
    add_column :entity_settings, :db_dumps_retention_period, :integer, default: 7
    add_column :entity_settings, :db_dumps_email_enabled, :boolean, default: false
  end
end
