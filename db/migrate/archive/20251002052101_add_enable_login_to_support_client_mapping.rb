class AddEnableLoginToSupportClientMapping < ActiveRecord::Migration[8.0]
  def change
    add_column :support_client_mappings, :enable_user_login, :boolean, default: false
    add_column :support_client_mappings, :user_emails, :string
  end
end
