class AddNoLinksToCustomNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :no_link, :boolean, default: false
  end
end
