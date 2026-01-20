class DropRubyLlmTables < ActiveRecord::Migration[8.0]
  def up
    # Handle dependencies before dropping chats
    if table_exists?(:ai_presentations) && column_exists?(:ai_presentations, :chat_id)
      remove_foreign_key :ai_presentations, :chats if foreign_key_exists?(:ai_presentations, :chats)
    end

    drop_table :tool_calls, if_exists: true
    drop_table :messages, if_exists: true
    drop_table :chats, if_exists: true
  end

  def down
    # No-op: we are reinstalling later
  end
end
