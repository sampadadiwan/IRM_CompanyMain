class RenameParentFolderToParent < ActiveRecord::Migration[7.0]
  def change
    rename_column :folders, :parent_folder_id, :parent_id
  end
end
