class AddNameToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :first_name, :string, limit: 20
    add_column :investor_kycs, :last_name, :string, limit: 20
    add_column :investor_kycs, :email, :string
    add_column :investor_kycs, :send_confirmation, :boolean, default: false
  end
end
