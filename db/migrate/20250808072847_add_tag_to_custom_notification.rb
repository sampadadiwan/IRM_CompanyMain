class AddTagToCustomNotification < ActiveRecord::Migration[8.0]
  def change
    add_column :custom_notifications, :tag, :string, limit: 30
  end
end
