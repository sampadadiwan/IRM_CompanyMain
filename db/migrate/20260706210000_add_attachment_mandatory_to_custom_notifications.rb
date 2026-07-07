class AddAttachmentMandatoryToCustomNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :custom_notifications, :attachment_mandatory, :boolean, default: false, null: false
  end
end
