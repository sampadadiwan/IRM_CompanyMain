class AddPhoneToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :phone, :string, limit: 12
  end
end
