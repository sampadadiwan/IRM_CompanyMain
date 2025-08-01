class AddPanToKycData < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:kyc_data, :PAN)
      add_column :kyc_data, :PAN, :string, limit: 10
    end
    unless column_exists?(:kyc_data, :name)
      add_column :kyc_data, :name, :string
    end
    unless column_exists?(:kyc_data, :external_identifier)
      add_column :kyc_data, :external_identifier, :string
    end
    unless column_exists?(:kyc_data, :birth_date)
      add_column :kyc_data, :birth_date, :datetime
    end
    unless column_exists?(:kyc_data, :status)
      add_column :kyc_data, :status, :string, limit: 20
    end
    # add 
  end
end
