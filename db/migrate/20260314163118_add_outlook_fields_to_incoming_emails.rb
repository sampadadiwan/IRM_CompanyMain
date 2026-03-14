class AddOutlookFieldsToIncomingEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :incoming_emails, :cc_emails, :string unless column_exists?(:incoming_emails, :cc_emails)
    add_column :incoming_emails, :message_id, :string unless column_exists?(:incoming_emails, :message_id)
    add_column :incoming_emails, :internet_message_id, :string unless column_exists?(:incoming_emails, :internet_message_id)
    add_column :incoming_emails, :received_at, :datetime unless column_exists?(:incoming_emails, :received_at)
    add_reference :incoming_emails, :filed_by_user, null: true, foreign_key: { to_table: :users } unless column_exists?(:incoming_emails, :filed_by_user_id)
  end
end
