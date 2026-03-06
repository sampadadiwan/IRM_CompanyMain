class AddCustomFieldsToChats < ActiveRecord::Migration[8.0]
  def change
    add_reference :chats, :entity
    add_reference :chats, :user
    add_reference :chats, :owner, polymorphic: true, null: true
    add_column :chats, :name, :string
    add_column :chats, :enable_broadcast, :boolean, default: true, null: false
    add_column :chats, :assistant_type, :string, limit: 50
    add_column :tool_calls, :thought_signature, :text

    # Update existing records (if any)
    reversible do |dir|
      dir.up do
        Chat.where(enable_broadcast: nil).update_all(enable_broadcast: true)
      end
    end
  end
end
