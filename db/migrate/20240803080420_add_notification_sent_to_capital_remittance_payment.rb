class AddNotificationSentToCapitalRemittancePayment < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_remittance_payments, :payment_notification_sent, :boolean, default: false
  end
end
