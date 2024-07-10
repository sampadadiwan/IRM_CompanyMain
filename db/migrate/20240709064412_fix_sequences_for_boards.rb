class FixSequencesForBoards < ActiveRecord::Migration[7.1]
  def change
    kanban_boards = KanbanBoard.all
    kanban_boards.each do |kb|
      kb.kanban_columns.each do |column|
        column.kanban_cards.each_with_index do |card, i|
          card.sequence = i + 1
          card.save!
        end
      end
    end
  end
end
