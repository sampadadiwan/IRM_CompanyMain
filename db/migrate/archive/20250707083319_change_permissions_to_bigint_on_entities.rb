class ChangePermissionsToBigintOnEntities < ActiveRecord::Migration[8.0]
  def change
    change_column :entities, :permissions, :bigint
  end
end
