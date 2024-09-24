class AddSequenceToKanbanCard < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :sequence, :integer
    add_index :kanban_cards, :sequence
  end
end
