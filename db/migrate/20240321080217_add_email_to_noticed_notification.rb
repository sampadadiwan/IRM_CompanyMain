# Temporarily define the Notification model to access the old table
class Notification < ActiveRecord::Base
  self.inheritance_column = nil
end

class AddEmailToNoticedNotification < ActiveRecord::Migration[7.1]
  def change
    # Migrate each record to the new tables
    Notification.find_each do |notification|
      attributes = notification.attributes.slice("type", "created_at", "updated_at").with_indifferent_access
      attributes[:type] = attributes[:type].sub("Notification", "Notifier")
      attributes[:params] = Noticed::Coder.load(notification.params)
      attributes[:params] = {} if attributes[:params].try(:has_key?, "noticed_error") # Skip invalid records

      # Extract related record to `belongs_to :record` association
      # This allows ActiveRecord associations instead of querying the JSON data
      # attributes[:record] = attributes[:params].delete(:user) || attributes[:params].delete(:account)

      attributes[:notifications_attributes] = [{
        type: "#{attributes[:type]}::Notification",
        recipient_type: notification.recipient_type,
        recipient_id: notification.recipient_id,
        read_at: notification.read_at,
        seen_at: notification.read_at,
        created_at: notification.created_at,
        updated_at: notification.updated_at
      }]
      Noticed::Event.create!(attributes)
    end

    # Noticed::Notification.find_each do |notification|
    #   notification.update(type: notification.type.sub("Notification", "Notifier"))
    # end

    add_column :noticed_notifications, :email_sent, :boolean, default: false  
    add_column :noticed_notifications, :email, :json
    add_column :noticed_notifications, :whatsapp_sent, :boolean, default: false  
    add_column :noticed_notifications, :whatsapp, :text
  end
end
