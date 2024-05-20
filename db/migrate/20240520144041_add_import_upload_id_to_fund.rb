class AddImportUploadIdToFund < ActiveRecord::Migration[7.1]
  def change
    add_reference :funds, :import_upload, null: true, foreign_key: true
  end
end
