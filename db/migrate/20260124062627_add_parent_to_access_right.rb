class AddParentToAccessRight < ActiveRecord::Migration[8.1]
  def change
    add_column :access_rights, :parent_access_right_id, :integer
  end
end
