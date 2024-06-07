class AddAdditionFieldsToCards < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:kanban_cards, :title)
      add_column :kanban_cards, :title, :string
    end
    unless column_exists?(:kanban_cards, :info_field)
      add_column :kanban_cards, :info_field, :string
    end
    unless column_exists?(:kanban_cards, :notes)
      add_column :kanban_cards, :notes, :text
    end
    unless column_exists?(:kanban_cards, :tags)
      add_column :kanban_cards, :tags, :string
    end
  end
end
