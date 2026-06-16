class AddImportUploadIdToDealActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :deal_activities, :import_upload_id, :bigint
    add_index :deal_activities, :import_upload_id
  end
end
