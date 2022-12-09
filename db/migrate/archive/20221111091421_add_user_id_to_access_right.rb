class AddUserIdToAccessRight < ActiveRecord::Migration[7.0]
  def change
    add_reference :access_rights, :user, null: true, foreign_key: true
  end
end
