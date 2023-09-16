class AddOrigRolesToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :advisor_entity_roles, :string, limit: 50
  end
end
