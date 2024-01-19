class AddPassProtectToCustomNotifications < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :password_protect_attachment, :boolean, default: false
    add_column :custom_notifications, :attachment_password, :string
  end
end
