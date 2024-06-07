class CreateKanbanBoard < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_boards do |t|
      t.string :name
      t.integer :owner_id
      t.string :owner_type
      t.datetime :deleted_at
      t.timestamps

      t.references :entity, null: false, foreign_key: true
    end

    add_index :kanban_boards, [:owner_id, :owner_type]
  end
end
