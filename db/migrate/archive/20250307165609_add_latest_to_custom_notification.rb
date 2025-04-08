class AddLatestToCustomNotification < ActiveRecord::Migration[7.2]
  def change
    add_column :custom_notifications, :latest, :boolean, default: true

    # Ensure Rails knows about the new column
    CustomNotification.reset_column_information

    # Fetch all unique combinations of email_method, entity_id, owner_id, owner_type
    unique_groups = CustomNotification.select(:email_method, :entity_id, :owner_id, :owner_type).distinct

    unique_groups.each do |group|
      # Find all matching records for this group
      notifications = CustomNotification.where(
        email_method: group.email_method,
        entity_id: group.entity_id,
        owner_id: group.owner_id,
        owner_type: group.owner_type
      ).order(created_at: :desc)

      # Mark all as latest: false
      notifications.update_all(latest: false)

      # Mark the most recent one as latest: true
      latest_record = notifications.first
      latest_record.update_columns(latest: true, enabled: true) if latest_record

    end

  end
end
