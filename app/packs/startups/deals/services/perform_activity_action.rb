class PerformActivityAction < Trailblazer::Operation
  step :validate_action_perform!
  step :mark_action_done!
  step :update_deal_investor
  step :broadcast_changes

  private

  def validate_action_perform!(ctx, params:, **)
    deal_investor = DealInvestor.find_by(id: params[:deal_investor_id])
    unless deal_investor.deal_activity.id.to_s == params[:initial_deal_activity_id]
      # TODO: Abhay - Use en.yml for messages
      ctx[:errors] = "Kanban Board unupdated"
      return false
    end
    ctx[:deal_investor] = deal_investor
  end

  def mark_action_done!(_ctx, deal_activity:, **)
    deal_activity.Complete!
  end

  def update_deal_investor(_ctx, params:, deal_investor:, **)
    target_deal_activity = DealActivity.find_by(id: params[:target_deal_activity_id])
    deal_investor.deal_activity = target_deal_activity
    deal_investor.save!
  end

  def broadcast_changes(ctx, deal_activity:, **)
    ctx[:errors] = deal_activity.errors.full_messages
    deal_activity.deal.kanban_board.broadcast_board_event if deal_activity.deal.kanban_board.present?
    true
  end
end
