class CreateTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :tasks do |t|
      t.text :details
      t.references :entity, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.integer :filter_id
      t.boolean :completed, default: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
