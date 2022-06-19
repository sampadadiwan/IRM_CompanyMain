class AddOwnerToTask < ActiveRecord::Migration[7.0]
  def change
    add_reference :tasks, :owner, polymorphic: true, null: true
    remove_column :tasks, :filter_id
  end
end
