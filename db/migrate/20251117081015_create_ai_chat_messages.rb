class CreateAiChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_chat_messages do |t|
      t.references :ai_chat_session, null: false, foreign_key: true
      t.string :role
      t.text :content
      t.json  :metadata

      t.timestamps
    end
  end
end
