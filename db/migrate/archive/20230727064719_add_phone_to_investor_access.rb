class AddPhoneToInvestorAccess < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_accesses, :phone, :string, limit: 15
    add_column :investor_accesses, :whatsapp_enabled, :boolean, default: false
  end
end
