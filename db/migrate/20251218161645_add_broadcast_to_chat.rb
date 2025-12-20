class AddBroadcastToChat < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :enable_broadcast, :boolean, default: true, null: false
    add_column :chats, :assistant_type, :string, limit: 50
    Chat.where(enable_broadcast: nil).update_all(enable_broadcast: true)
  end
end
