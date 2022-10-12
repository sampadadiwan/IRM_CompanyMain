class AddVerifiedToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :verified, :boolean, default: false
  end
end
