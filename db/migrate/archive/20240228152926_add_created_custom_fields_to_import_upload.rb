class AddCreatedCustomFieldsToImportUpload < ActiveRecord::Migration[7.1]
  def change
    add_column :import_uploads, :custom_fields_created, :text
  end
end
