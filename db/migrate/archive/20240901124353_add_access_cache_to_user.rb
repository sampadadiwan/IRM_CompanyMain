class AddAccessCacheToUser < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :access_rights_cache, :text
  end
end
