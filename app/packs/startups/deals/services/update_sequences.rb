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
    non_template_deal_activites = DealActivity.not_templates(ctx[:deal]).where(title: deal_activity.title)
    non_template_deal_activites.each do |not_template_deal_activity|
      not_template_deal_activity.sequence = deal_activity.sequence
      not_template_deal_activity.save!
    end
    true
  end

  def broadcast_changes(_ctx, deal_activity:, **)
    deal_activity.deal.kanban_board.broadcast_board_event if deal_activity.deal.kanban_board.present?
    true
  end
end
