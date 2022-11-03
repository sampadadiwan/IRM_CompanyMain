class AddDisableKycToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :disable_pan_kyc, :boolean, default: false
    add_column :secondary_sales, :disable_bank_kyc, :boolean, default: false
  end
end
