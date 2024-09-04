class AddAccessRightsCachedPermissionsToUser < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :access_rights_cached_permissions, :integer
  end
end
