class UpdateSequences < Trailblazer::Operation
  step :update_sequences
  step :update_non_template_deal_activities
  step :broadcast_changes

  private

  def update_sequences(ctx, params:, **)
    ctx[:deal_activity] = DealActivity.find(params[:dragged_column_id])
    ctx[:deal_activity].sequence = params[:new_position]
    ctx[:deal_activity].save!
    true
  end

  def update_non_template_deal_activities(ctx, deal_activity:, **)
    ctx[:deal] = deal_activity.deal
    DealActivity.not_templates(ctx[:deal]).where(template_id: deal_activity.id)
                .update_all(sequence: deal_activity.sequence) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  def broadcast_changes(_ctx, deal_activity:, **)
    deal_activity.deal.kanban_board.presence&.broadcast_board_event
    true
  end
end
