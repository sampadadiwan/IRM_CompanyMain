class AddNotificationSentToCapitalDistributionPayment < ActiveRecord::Migration[8.0]
  def change
    add_column :capital_distribution_payments, :notification_sent, :boolean, default: false, null: false
    # All old completed records are considered notified
    CapitalDistributionPayment.completed.update_all(notification_sent: true)
  end
end
