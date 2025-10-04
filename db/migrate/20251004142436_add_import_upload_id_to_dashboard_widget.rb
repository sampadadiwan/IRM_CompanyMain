class AddImportUploadIdToDashboardWidget < ActiveRecord::Migration[8.0]
  def change
    add_column :dashboard_widgets, :import_upload_id, :integer
    add_index :dashboard_widgets, :import_upload_id
  end
end
