class UpdateCardsJob < ApplicationJob
  def perform(kanban_board_id, card_view_attrs)
    kanban_board = KanbanBoard.find(kanban_board_id)
    kanban_board.update_cards(card_view_attrs)

    # broadcast to all users
    kanban_board.broadcast_board_event
  end
end
