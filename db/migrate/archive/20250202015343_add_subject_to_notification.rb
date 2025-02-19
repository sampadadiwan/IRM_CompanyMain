class AddSubjectToNotification < ActiveRecord::Migration[7.2]
  def change
    add_column :noticed_notifications, :subject, :string
    Noticed::Notification.all.each do |n|
      n.update_column(:subject, n.message.truncate(254))
    end
  end
end
