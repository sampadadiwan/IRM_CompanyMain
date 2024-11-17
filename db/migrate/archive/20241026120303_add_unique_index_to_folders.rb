class AddUniqueIndexToFolders < ActiveRecord::Migration[7.1]
  def change
    add_index :folders, [:full_path, :owner_id, :owner_type, :entity_id, :deleted_at], unique: true, name: 'index_folders_on_full_path_and_owner_entity_with_deleted_at'
  end

  def down
    remove_index :folders, name: 'index_folders_on_full_path_and_owner_entity_with_deleted_at'
  end
end
