class AddEmailMethodToCustomNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :email_method, :string, limit: 100
    rename_column :custom_notifications, :for, :for_type
  end
end
