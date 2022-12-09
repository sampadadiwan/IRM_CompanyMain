class ChangeUserInAdhaarEsign < ActiveRecord::Migration[7.0]
  def change
    remove_reference :adhaar_esigns, :user, index: true, foreign_key: true
    add_column :adhaar_esigns, :user_ids, :string
  end
end
