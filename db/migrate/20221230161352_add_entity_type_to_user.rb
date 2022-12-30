class AddEntityTypeToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :entity_type, :string, limit: 25
    User.update_roles
  end
end
