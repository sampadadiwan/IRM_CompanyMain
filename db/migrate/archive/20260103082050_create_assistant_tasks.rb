class CreateAssistantTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :assistant_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :assistant_type, limit: 50
      t.string :assistant_metadata
      t.string :period, limit: 10
      t.string :tag_list
      t.text :instructions

      t.timestamps
    end
  end
end
