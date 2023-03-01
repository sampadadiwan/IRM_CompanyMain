class AddVirtualBankToCApitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :virtual_bank_account, :string, limit: 20
  end
end
