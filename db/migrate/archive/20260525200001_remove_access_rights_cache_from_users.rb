class RemoveAccessRightsCacheFromUsers < ActiveRecord::Migration[7.1]
  # Removes the serialized access_rights_cache (Hash) and the temporary
  # access_rights_cached_permissions (bitmask) columns from users.
  # ApplicationPolicy now queries the access_rights table directly, so these
  # columns are no longer written or read anywhere.
  def up
    remove_column :users, :access_rights_cache
    remove_column :users, :access_rights_cached_permissions
  end

  def down
    add_column :users, :access_rights_cache, :text
    add_column :users, :access_rights_cached_permissions, :bigint, default: 0, null: false
  end
end
