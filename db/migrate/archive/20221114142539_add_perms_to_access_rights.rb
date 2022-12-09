class AddPermsToAccessRights < ActiveRecord::Migration[7.0]
  def change
    add_column :access_rights, :permissions, :integer, null: false, default: 0, limit: 8
  end
end
