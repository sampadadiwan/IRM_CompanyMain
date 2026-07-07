class AddSkipTrackingToNoticedNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :noticed_notifications, :skip_reason, :string
    add_column :noticed_notifications, :skip_reported_at, :datetime
  end
end
