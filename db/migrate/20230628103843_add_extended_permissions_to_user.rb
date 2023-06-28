class AddExtendedPermissionsToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :extended_permissions, :integer, default: 0
  end
end
