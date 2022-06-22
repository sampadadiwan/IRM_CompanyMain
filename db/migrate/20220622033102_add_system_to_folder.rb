class AddSystemToFolder < ActiveRecord::Migration[7.0]
  def change
    add_column :folders, :folder_type, :integer, default: 0
    add_column :folders, :owner_id, :integer, default: 0    
  end
end
