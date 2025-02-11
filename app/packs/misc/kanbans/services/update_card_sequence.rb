class UpdateCardSequence < Trailblazer::Operation
  step :update_card_sequences

  private

  def update_card_sequences(ctx, params:, kanban_card:, **)
    kanban_card.sequence = params[:new_position]
    kanban_card.save!
    ctx[:kanban_board] = kanban_card.kanban_board
    true
  end
end
