class AddEmailDelayToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :email_delay_seconds, :integer, default: 0
  end
end
