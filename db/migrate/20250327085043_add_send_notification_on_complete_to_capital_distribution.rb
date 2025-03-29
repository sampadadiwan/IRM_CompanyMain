class AddSendNotificationOnCompleteToCapitalDistribution < ActiveRecord::Migration[8.0]
  def change
    add_column :capital_distributions, :send_notification_on_complete, :boolean, default: true
  end
end
