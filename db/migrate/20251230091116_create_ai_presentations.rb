class CreateAiPresentations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_presentations do |t|
      t.references :chat, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.text :content_html, size: :long
      t.text :blueprint, size: :long

      t.timestamps
    end
  end
end
