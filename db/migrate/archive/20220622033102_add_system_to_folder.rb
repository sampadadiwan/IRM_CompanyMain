class AddSystemToFolder < ActiveRecord::Migration[7.0]
  def change
    add_column :folders, :folder_type, :integer, default: 0
    add_reference :folders, :owner, polymorphic: true, null: true
  end
end
