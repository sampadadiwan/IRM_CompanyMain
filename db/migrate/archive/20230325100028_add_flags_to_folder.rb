class AddFlagsToFolder < ActiveRecord::Migration[7.0]
  def change
    add_column :folders, :download, :boolean, default: false
    add_column :folders, :printing, :boolean, default: false
    add_column :folders, :orignal, :boolean, default: false
  end
end
