class CreateKanbanColumn < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_columns do |t|
      t.string :name
      t.integer :sequence
      t.datetime :deleted_at

      t.references :entity, null: false, foreign_key: true
      t.references :kanban_board, null: false, foreign_key: true
      t.timestamps
    end
  end
end
