class AddBankAccountToFee < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :bank_account_number, :string, limit: 40
    add_column :fees, :ifsc_code, :string, limit: 20
  end
end
