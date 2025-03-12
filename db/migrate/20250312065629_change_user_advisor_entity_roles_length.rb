class ChangeUserAdvisorEntityRolesLength < ActiveRecord::Migration[7.2]
  def change
    change_column :users, :advisor_entity_roles, :string, limit: 100
  end
end
