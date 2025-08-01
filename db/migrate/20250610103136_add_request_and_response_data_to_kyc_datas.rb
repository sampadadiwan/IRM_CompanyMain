class AddRequestAndResponseDataToKycDatas < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:kyc_data, :request_data)
      add_column :kyc_data, :request_data, :json
    end
    unless column_exists?(:kyc_data, :response_data)
      add_column :kyc_data, :response_data, :json
    end
  end
end
