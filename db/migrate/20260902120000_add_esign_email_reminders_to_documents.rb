class AddEsignEmailRemindersToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :esign_email_reminders, :boolean, default: true, null: false, if_not_exists: true
  end
end
