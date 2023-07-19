class AddGRantedByToAccessRight < ActiveRecord::Migration[7.0]
  def change
    add_reference :access_rights, :granted_by, null: true, foreign_key: {to_table: :users}
  end
end
