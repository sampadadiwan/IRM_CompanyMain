module KanbanManager
  extend ActiveSupport::Concern

  included do
    has_one :kanban_board, as: :owner, dependent: :destroy
    after_create :create_kanban_board
    after_update :update_kanban_board
  end

  def create_kanban_board
    KanbanBoard.create(name:, owner_id: id, entity_id:, owner_type: "Deal")
  end

  def update_kanban_board
    kanban_board.update(name:) if saved_change_to_name?
    UpdateCardsJob.perform_later(kanban_board.id, card_view_attrs) if saved_change_to_card_view_attrs?
  end
end
