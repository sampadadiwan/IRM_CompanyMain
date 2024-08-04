class AddSendNotificationToCapitalCall < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_calls, :send_call_notice_flag, :boolean, default: true
    add_column :capital_calls, :send_payment_notification_flag, :boolean, default: true
  end
end
