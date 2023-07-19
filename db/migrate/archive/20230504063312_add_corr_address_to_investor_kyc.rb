class AddCorrAddressToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :corr_address, :text
  end
end
