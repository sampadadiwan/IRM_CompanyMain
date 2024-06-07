class CreateKanbanCard < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_cards do |t|
      t.integer :data_source_id
      t.string :data_source_type
      t.datetime :deleted_at

      t.references :entity, null: false, foreign_key: true
      t.references :kanban_board, null: false, foreign_key: true
      t.references :kanban_column, null: false, foreign_key: true
      t.timestamps
    end
    add_index :kanban_cards, [:data_source_type, :data_source_id]
  end
end
