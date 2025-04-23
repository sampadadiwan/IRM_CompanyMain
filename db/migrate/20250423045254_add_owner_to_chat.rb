class AddOwnerToChat < ActiveRecord::Migration[8.0]
  def change
    add_reference :chats, :owner, polymorphic: true, null: true
    add_column :chats, :name, :string
  end
end
