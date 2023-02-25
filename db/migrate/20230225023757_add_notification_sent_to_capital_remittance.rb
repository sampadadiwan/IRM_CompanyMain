class AddNotificationSentToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :notification_sent, :boolean, default: false
  end
end
