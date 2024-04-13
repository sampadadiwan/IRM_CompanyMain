class AddDeletedAtToCustomNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :deleted_at, :datetime
    add_index :custom_notifications, :deleted_at
    add_column :custom_notifications, :enabled, :boolean, default: true
    # Rename Commitment Agreement to Send Document
    CustomNotification.where(for_type: "Commitment Agreement").update_all(for_type: "Send Document")
  end
end
