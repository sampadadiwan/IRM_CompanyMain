class AddShowEmbeddedToDocument < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :embed, :boolean, default: false
  end
end
