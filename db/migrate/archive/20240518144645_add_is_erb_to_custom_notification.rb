class AddIsErbToCustomNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :is_erb, :boolean, default: false
  end
end
