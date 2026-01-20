class CreateAiChatSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_chat_sessions do |t|
      t.references :ai_portfolio_report, null: false, foreign_key: true
      t.integer :analyst_id

      t.timestamps
    end
  end
end
