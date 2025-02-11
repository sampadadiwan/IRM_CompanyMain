class RestoreColumn < Trailblazer::Operation
  step :restore_column
  step :broadcast_changes

  private

  def restore_column(_ctx, kanban_column:, **)
    archived_cards = kanban_column.kanban_cards.only_deleted
    archived_cards.each(&:restore!)
    kanban_column.restore!
    kanban_columns = kanban_column.kanban_board.kanban_columns
    # rubocop : disable Rails/SkipsModelValidations
    kanban_columns.each_with_index do |column, index|
      column.update_column(:sequence, index + 1)
    end
    # rubocop : enable Rails/SkipsModelValidations
  end

  def broadcast_changes(_ctx, kanban_column:, **)
    kanban_column.kanban_board.broadcast_board_event
  end
end
