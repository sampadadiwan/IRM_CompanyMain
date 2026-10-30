class AddEsignReminderPeriodToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :esign_reminder_period, :integer, if_not_exists: true
  end
end
