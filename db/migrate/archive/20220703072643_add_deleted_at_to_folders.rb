class AddDeletedAtToFolders < ActiveRecord::Migration[7.0]
  def change
    add_column :folders, :deleted_at, :datetime
    add_index :folders, :deleted_at
  end
end
