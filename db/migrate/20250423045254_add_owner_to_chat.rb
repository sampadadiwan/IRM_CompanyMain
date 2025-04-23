class AddOwnerToChat < ActiveRecord::Migration[8.0]
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
  
    add_reference :chats, :owner, polymorphic: true, null: true
    add_column :chats, :name, :string
  end
end
