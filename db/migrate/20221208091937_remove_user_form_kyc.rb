class RemoveUserFormKyc < ActiveRecord::Migration[7.0]
  def change
    remove_reference :investor_kycs, :user
    remove_column :investor_kycs, :first_name
    remove_column :investor_kycs, :last_name
    remove_column :investor_kycs, :email
    remove_column :investor_kycs, :phone
    remove_column :investor_kycs, :send_confirmation
  end
end
