class AddOwnerTagToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :owner_tag, :string, limit: 20
  end
end
