class AddBranchToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :bank_name, :string, limit: 50
    add_column :investor_kycs, :bank_branch, :string, limit: 40
    add_column :investor_kycs, :bank_account_type, :string, limit: 40
  end
end
