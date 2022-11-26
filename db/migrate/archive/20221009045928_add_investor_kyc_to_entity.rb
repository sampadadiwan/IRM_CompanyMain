class AddInvestorKycToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_investor_kyc, :boolean, default: false
  end
end
