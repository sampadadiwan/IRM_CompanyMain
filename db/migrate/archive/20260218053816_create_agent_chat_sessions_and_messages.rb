class CreateAgentChatSessionsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_chat_sessions do |t|
      t.references :support_agent, null: false, foreign_key: true
      t.references :analyst, null: false, foreign_key: { to_table: :users }
      t.string :chattable_type, limit: 50
      t.bigint :chattable_id
      t.timestamps
    end

    add_index :agent_chat_sessions, [:chattable_type, :chattable_id],
              name: 'index_agent_chat_sessions_on_chattable'
    add_index :agent_chat_sessions, [:support_agent_id, :chattable_type, :chattable_id, :analyst_id],
              unique: true, name: 'index_agent_chat_sessions_uniqueness'

    create_table :agent_chat_messages do |t|
      t.references :agent_chat_session, null: false, foreign_key: true
      t.string :role, null: false, limit: 20
      t.text :content, null: false
      t.json :metadata
      t.timestamps
    end
  end
end
