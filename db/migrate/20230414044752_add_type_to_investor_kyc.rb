class AddTypeToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :kyc_type, :string, limit: 15, default: "Individual"
    InvestorKyc.update_all(kyc_type: "Individual")
  end
end
