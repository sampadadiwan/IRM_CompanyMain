class ArchiveKanbanColumn < Trailblazer::Operation
  step :delete_kanban_column
  step :broadcast_changes

  private

  def delete_kanban_column(_ctx, kanban_column:, **)
    kanban_column.kanban_cards.each(&:destroy)
    kanban_column.destroy
    kanban_columns = kanban_column.kanban_board.kanban_columns
    # rubocop : disable Rails/SkipsModelValidations
    kanban_columns.each_with_index do |column, index|
      column.update_column(:sequence, index + 1)
    end
    # rubocop : enable Rails/SkipsModelValidations
    true
  end

  def broadcast_changes(_ctx, kanban_column:, **)
    kanban_column.kanban_board.broadcast_board_event
  end
end
