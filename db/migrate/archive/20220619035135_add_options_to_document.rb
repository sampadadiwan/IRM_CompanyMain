class AddOptionsToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :download, :boolean, default: false
    add_column :documents, :printing, :boolean, default: false
  end
end
