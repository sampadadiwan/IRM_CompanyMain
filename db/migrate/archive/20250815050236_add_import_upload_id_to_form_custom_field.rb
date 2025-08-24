class AddImportUploadIdToFormCustomField < ActiveRecord::Migration[8.0]
  def change
    # Add import_upload_id to form_custom_fields table
    add_column :form_custom_fields, :import_upload_id, :integer, null: true, comment: "ID of the import upload that created or updated this form custom field"
    add_index :form_custom_fields, :import_upload_id, name: "index_form_custom_fields_on_import_upload_id"

    # This was missing so adding it here
    add_index :account_entries, :import_upload_id, name: "index_account_entries_on_import_upload_id"
  end
end
