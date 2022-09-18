class AddIndexToAccessRight < ActiveRecord::Migration[7.0]
  def change
    add_index :access_rights, :access_to_investor_id
  end
end
