class RenameNoLinkInCustomNotifications < ActiveRecord::Migration[8.0]
  def change
    reversible do |dir|
      dir.up do
        # Rename the column in the custom_notifications table
        rename_column :custom_notifications, :no_link, :show_details_link

        # Update the default value for the new column
        change_column_default :custom_notifications, :show_details_link, from: false, to: true

        # Update existing records to set the new column value based on the old column value
        CustomNotification.reset_column_information
        CustomNotification.update_all("show_details_link = NOT show_details_link")
      end

      dir.down do
        # Rename the column back to its original name
        rename_column :custom_notifications, :show_details_link, :no_link
        # Revert the default value change
        change_column_default :custom_notifications, :no_link, from: true, to: false
        # Update existing records to set the old column value based on the new column value
        CustomNotification.reset_column_information
        CustomNotification.update_all("no_link = NOT no_link")
      end
    end
  end
end
