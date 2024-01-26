class AddStatusToNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :notifications, :email_sent, :boolean, default: false
    add_column :notifications, :email, :text
    add_column :notifications, :whatsapp_sent, :boolean, default: false
    add_column :notifications, :whatsapp, :text

    puts "Deleting old notifications"
    Notification.where(created_at: ..(Date.today - 1.month)).each(&:destroy)
    puts "Updating notifications"
    Notification.update_all(email_sent: true, whatsapp_sent: true)
    puts "Updating notification msg"
    Notification.all.each do |n|
      begin
        n.params["msg"] = n.to_notification.message
        n.save
      rescue
      end
    end
  end

  
end
