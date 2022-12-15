class DropFileFieldsInDocument < ActiveRecord::Migration[7.0]
  def change
    remove_column :documents, :file_file_name
    remove_column :documents, :file_content_type
    remove_column :documents, :file_file_size
    remove_column :documents, :file_updated_at
  end
end
