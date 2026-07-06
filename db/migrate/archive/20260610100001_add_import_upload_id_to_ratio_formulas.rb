class AddImportUploadIdToRatioFormulas < ActiveRecord::Migration[7.2]
  def change
    add_column :ratio_formulas, :import_upload_id, :bigint
    add_index :ratio_formulas, :import_upload_id
  end
end
