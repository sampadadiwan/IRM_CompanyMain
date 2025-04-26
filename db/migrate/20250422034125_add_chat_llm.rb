class AddChatLlm < ActiveRecord::Migration[8.0]
  def change
    create_table :chats do |t|
      t.string :model_id
      t.references :entity, null: false, foreign_key: true # Entity the chat is associated with
      t.references :user, null: false, foreign_key: true # User who initiated the chat
      t.timestamps
    end
  
    drop_table :messages, if_exists: true # Drop old table if it exists
    create_table :messages do |t|
      t.references :chat, null: false, foreign_key: true
      t.string :role
      t.text :content
      # Optional fields for tracking usage/metadata
      t.string :model_id
      t.integer :input_tokens
      t.integer :output_tokens
      t.references :tool_call # Links tool result message to the initiating call
      t.timestamps
    end
  
    create_table :tool_calls do |t|
      t.references :message, null: false, foreign_key: true # Assistant message making the call
      t.string :tool_call_id, null: false, index: { unique: true } # Provider's ID for the call
      t.string :name, null: false
      t.json :arguments # Use jsonb for PostgreSQL
      t.timestamps
    end
  end
end
