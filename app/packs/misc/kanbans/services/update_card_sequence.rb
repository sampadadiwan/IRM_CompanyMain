class UpdateCardSequence < Trailblazer::Operation
  step :update_card_sequences
  step :broadcast_changes

  private

  def update_card_sequences(ctx, params:, kanban_card:, **)
    kanban_card.sequence = params[:new_position]
    kanban_card.save!
    ctx[:kanban_board] = kanban_card.kanban_board
    true
  end

  def broadcast_changes(_ctx, kanban_board:, **)
    ActionCable.server.broadcast(EventsChannel::BROADCAST_CHANNEL, kanban_board.broadcast_data)
    true
  end
end
