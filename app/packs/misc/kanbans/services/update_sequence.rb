class UpdateSequence < Trailblazer::Operation
  step :update_sequence
  step :broadcast_changes

  private

  def update_sequence(_ctx, params:, kanban_column:, **)
    kanban_column.sequence = params["new_position"]
    kanban_column.save!
    true
  end

  def broadcast_changes(_ctx, kanban_column:, **)
    ActionCable.server.broadcast(EventsChannel::BROADCAST_CHANNEL, kanban_column.kanban_board.broadcast_data)
    true
  end
end
