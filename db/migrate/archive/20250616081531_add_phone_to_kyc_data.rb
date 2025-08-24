class AddPhoneToKycData < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:kyc_data, :phone)
      add_column :kyc_data, :phone, :string, limit: 10
    end
  end
end
