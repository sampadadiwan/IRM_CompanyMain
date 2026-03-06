class DropAiChatSessionsAndMessages < ActiveRecord::Migration[8.1]
  def up
    drop_table :ai_chat_messages
    drop_table :ai_chat_sessions
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
