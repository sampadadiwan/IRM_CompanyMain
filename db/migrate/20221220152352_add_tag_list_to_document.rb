class AddTagListToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :tag_list, :string, limit: 60
  end
end
