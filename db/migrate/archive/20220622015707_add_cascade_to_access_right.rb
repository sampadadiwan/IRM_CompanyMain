class AddCascadeToAccessRight < ActiveRecord::Migration[7.0]
  def change
    add_column :access_rights, :cascade, :boolean, default: false
  end
end
