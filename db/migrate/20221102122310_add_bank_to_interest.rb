class AddBankToInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :interests, :bank_account_number, :string, limit: 40
    add_column :interests, :ifsc_code, :string, limit: 20
  end
end
