class AddSendEmailToInvestorAccess < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_accesses, :email_enabled, :boolean, default: true
  end
end
