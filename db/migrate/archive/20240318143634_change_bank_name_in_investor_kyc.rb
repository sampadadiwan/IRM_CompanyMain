class ChangeBankNameInInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    change_column :investor_kycs, :bank_name, :string, limit: 100
  end
end
