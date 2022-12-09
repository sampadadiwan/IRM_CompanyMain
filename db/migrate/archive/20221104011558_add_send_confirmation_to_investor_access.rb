class AddSendConfirmationToInvestorAccess < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_accesses, :send_confirmation, :boolean, default: false
  end
end
