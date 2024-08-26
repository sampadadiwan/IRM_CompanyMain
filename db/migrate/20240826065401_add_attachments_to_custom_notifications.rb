class AddAttachmentsToCustomNotifications < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :attachment_names, :string
  end
end
