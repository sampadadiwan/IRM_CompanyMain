class CreateFaqThread < ActiveRecord::Migration[8.0]
  def change
    create_table :faq_threads do |t|
      t.references :user, null: false, foreign_key: true
      t.string :openai_thread_id
      t.string :title, default: "New Support Chat" # Optional: to label chats

      t.timestamps
    end
  end
end
