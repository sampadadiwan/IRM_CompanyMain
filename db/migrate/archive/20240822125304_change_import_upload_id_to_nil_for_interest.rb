class ChangeImportUploadIdToNilForInterest < ActiveRecord::Migration[7.1]
  def change
    change_column :interests, :import_upload_id, :bigint, null: true
  end
end
