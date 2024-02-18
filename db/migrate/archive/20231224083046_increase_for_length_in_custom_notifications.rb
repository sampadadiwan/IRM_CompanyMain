class IncreaseForLengthInCustomNotifications < ActiveRecord::Migration[7.1]
  def change
    change_column :custom_notifications, :for, :string, limit: 100
  end
end
