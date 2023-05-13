class ModifyAccessRightsNotify < ActiveRecord::Migration[7.0]
  def change
    change_column_default :access_rights, :notify, false 
  end
end
