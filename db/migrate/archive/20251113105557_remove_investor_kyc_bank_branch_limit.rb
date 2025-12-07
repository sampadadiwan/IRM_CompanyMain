class RemoveInvestorKycBankBranchLimit < ActiveRecord::Migration[8.0]
  def change
    change_column :investor_kycs, :bank_branch, :string
  end
end
