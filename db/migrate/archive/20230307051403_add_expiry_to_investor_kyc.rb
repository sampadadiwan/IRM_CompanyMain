class AddExpiryToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :expiry_date, :date
  end
end
