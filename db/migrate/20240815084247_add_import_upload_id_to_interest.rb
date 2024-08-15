class AddImportUploadIdToInterest < ActiveRecord::Migration[7.1]
  def change
    add_reference :interests, :import_upload, null: true, foreign_key: true
  end
end
