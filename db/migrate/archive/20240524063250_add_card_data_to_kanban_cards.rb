class AddCardDataToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :title, :string
    add_column :kanban_cards, :info_field, :string
    add_column :kanban_cards, :notes, :text
    add_column :kanban_cards, :tags, :string
  end
end
