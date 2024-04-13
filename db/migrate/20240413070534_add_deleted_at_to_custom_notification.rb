class AddDeletedAtToCustomNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :deleted_at, :datetime
    add_index :custom_notifications, :deleted_at
  end
end
