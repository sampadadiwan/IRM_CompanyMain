class AddNotificationSentToApprovalResponse < ActiveRecord::Migration[7.0]
  def change
    add_column :approval_responses, :notification_sent, :boolean, default: false
  end
end
