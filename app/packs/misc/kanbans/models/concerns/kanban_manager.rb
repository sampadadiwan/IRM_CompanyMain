module KanbanManager
  extend ActiveSupport::Concern

  included do
    has_one :kanban_board, as: :owner, dependent: :destroy
    after_create :create_kanban_board
  end

  def create_kanban_board
    KanbanBoard.create(name:, owner_id: id, entity_id:, owner_type: "Deal")
  end
end
