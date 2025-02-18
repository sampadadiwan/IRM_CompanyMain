class AddNotificationRetentionToEntitySetting < ActiveRecord::Migration[7.2]
  def change
    # default retention is for 2 months
    add_column :entity_settings, :notification_retention_months, :integer, default: 2
  end
end
