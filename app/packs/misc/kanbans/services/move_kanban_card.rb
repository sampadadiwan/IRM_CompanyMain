class MoveKanbanCard < Trailblazer::Operation
  step :validate_action_perform!
  step :move_kanban_card

  private

  def validate_action_perform!(ctx, params:, kanban_card:, **)
    unless kanban_card.kanban_column.id.to_s == params[:initial_kanban_column_id]
      ctx[:errors] = "Board unupdated"
      return false
    end
    true
  end

  def move_kanban_card(_ctx, params:, kanban_card:, **)
    target_kanban_column = KanbanColumn.find(params[:target_kanban_column_id])
    kanban_card.kanban_column = target_kanban_column
    kanban_card.save!
    true
  end
end
