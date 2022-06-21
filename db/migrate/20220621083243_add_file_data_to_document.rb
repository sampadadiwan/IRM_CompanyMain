class AddFileDataToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :file_data, :text
  end
end
