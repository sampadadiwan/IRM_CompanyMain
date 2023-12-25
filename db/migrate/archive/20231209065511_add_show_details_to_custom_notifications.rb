class AddShowDetailsToCustomNotifications < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_notifications, :show_details, :boolean, default: false
  end
end
