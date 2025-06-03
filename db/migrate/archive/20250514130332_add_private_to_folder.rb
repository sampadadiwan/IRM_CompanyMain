class AddPrivateToFolder < ActiveRecord::Migration[8.0]
  def change
    add_column :folders, :private, :boolean, default: false
  end
end
