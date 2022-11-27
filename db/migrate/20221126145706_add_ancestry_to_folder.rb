class AddAncestryToFolder < ActiveRecord::Migration[7.0]
  def change
    add_column :folders, :ancestry, :string
    add_index :folders, :ancestry
  end
  Folder.build_ancestry_from_parent_ids!
end
