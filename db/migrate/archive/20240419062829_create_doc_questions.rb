class CreateDocQuestions < ActiveRecord::Migration[7.1]
  def change
    create_table :doc_questions do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :tags, limit: 100
      t.text :question

      t.timestamps
    end
  end
end
