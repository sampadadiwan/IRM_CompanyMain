class PerformActivityAction < Trailblazer::Operation
  step :validate_action_perform!
  step :mark_action_done!
  step :update_deal_investor
  step :generate_step_tasks
  step :broadcast_changes

  private

  # Validates that the deal investor is currently on the expected step
  def validate_action_perform!(ctx, params:, **)
    deal_investor = DealInvestor.find_by(id: params[:deal_investor_id])
    unless deal_investor.deal_activity.id.to_s == params[:initial_deal_activity_id]
      # TODO: Abhay - Use en.yml for messages
      ctx[:errors] = "Kanban Board unupdated"
      return false
    end
    ctx[:deal_investor] = deal_investor
  end

  # Marks the previous activity as complete
  def mark_action_done!(_ctx, deal_activity:, **)
    deal_activity.Complete!
  end

  # Updates the deal investor to the target activity (step)
  def update_deal_investor(_ctx, params:, deal_investor:, **)
    target_deal_activity = DealActivity.find_by(id: params[:target_deal_activity_id])
    deal_investor.deal_activity = target_deal_activity
    deal_investor.save!
  end

  # Enqueues the job to generate tasks based on the new activity's tasks_csv field.
  # These tasks are assigned to the current user who performed the transition.
  def generate_step_tasks(ctx, deal_investor:, **)
    GenerateDealStepTasksJob.perform_later(deal_investor.id, ctx[:current_user_id] || ctx[:user_id])
    true
  end

  def broadcast_changes(ctx, deal_activity:, **)
    ctx[:errors] = deal_activity.errors.full_messages
    deal_activity.deal.kanban_board.presence&.broadcast_board_event
    true
  end
end
