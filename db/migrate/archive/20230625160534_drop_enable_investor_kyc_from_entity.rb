class DropEnableInvestorKycFromEntity < ActiveRecord::Migration[7.0]
  def change
    Entity.where(enable_investor_kyc: true).update_all(enable_kycs: true) 
    remove_column :entities, :enable_investor_kyc
  end
end
