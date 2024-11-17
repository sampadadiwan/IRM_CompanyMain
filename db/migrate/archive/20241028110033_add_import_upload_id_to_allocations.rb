class AddImportUploadIdToAllocations < ActiveRecord::Migration[7.1]
  def change
    add_column :allocations, :import_upload_id, :bigint
  end
end
