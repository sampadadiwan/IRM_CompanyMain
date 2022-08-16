class AddRoleToPermission < ActiveRecord::Migration[7.0]
  def change
    add_column :permissions, :role, :string, limit: 20
  end
end
