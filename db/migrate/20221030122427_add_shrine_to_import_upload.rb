class AddShrineToImportUpload < ActiveRecord::Migration[7.0]
  def change
    add_column :import_uploads, :import_file_data, :text
    add_column :import_uploads, :import_results_data, :text
  end
end
