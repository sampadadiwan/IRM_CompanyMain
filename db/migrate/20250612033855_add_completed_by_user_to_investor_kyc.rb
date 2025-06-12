class AddCompletedByUserToInvestorKyc < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kycs, :completed_by_investor, :boolean, default: false
    InvestorKyc.all.each do |investor_kyc|
      # Assuming that if the KYC is completed, it was done by the investor
      if investor_kyc.verified
        investor_kyc.update_column(:completed_by_investor, true)
      end
    end
  end
end
