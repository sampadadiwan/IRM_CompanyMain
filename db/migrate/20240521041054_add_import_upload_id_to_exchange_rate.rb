class AddImportUploadIdToExchangeRate < ActiveRecord::Migration[7.1]
  def change
    add_reference :exchange_rates, :import_upload, null: true, foreign_key: true
  end
end
