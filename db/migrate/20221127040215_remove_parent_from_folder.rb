class RemoveParentFromFolder < ActiveRecord::Migration[7.0]
  def change
    remove_column :folders, :parent_id
    remove_column :folders, :path_ids    
  end
end
