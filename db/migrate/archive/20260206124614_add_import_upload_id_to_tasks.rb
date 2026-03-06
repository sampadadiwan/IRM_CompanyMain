class AddImportUploadIdToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :import_upload_id, :integer
    add_index :tasks, :import_upload_id
  end
end
