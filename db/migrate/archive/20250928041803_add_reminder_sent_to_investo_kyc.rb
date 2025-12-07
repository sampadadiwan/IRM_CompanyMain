class AddReminderSentToInvestoKyc < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kycs, :reminder_sent, :boolean, default: false
    add_column :investor_kycs, :reminder_sent_date, :datetime, default: nil
  end
end
