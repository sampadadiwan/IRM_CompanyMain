class AddForToCustomNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :for, :string, limit: 15
  end
end
