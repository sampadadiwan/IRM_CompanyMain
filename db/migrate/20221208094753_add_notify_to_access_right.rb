class AddNotifyToAccessRight < ActiveRecord::Migration[7.0]
  def change
    add_column :access_rights, :notify, :boolean, default: true
  end
end
