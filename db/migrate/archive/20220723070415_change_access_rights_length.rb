class ChangeAccessRightsLength < ActiveRecord::Migration[7.0]
  def change
    change_column :access_rights, :access_type, :string, :limit => 25
  end
end
