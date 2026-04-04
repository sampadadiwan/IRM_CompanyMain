class CompleteDealActivity < Trailblazer::Operation
  step :save_activity!
  step :find_next_activity
  step :perform_next_action!

  private

  def save_activity!(_ctx, deal_activity:, params:, **)
    deal_activity.assign_attributes(params)
    deal_activity.save
  end

  # Find the next sequential activity after the one just completed
  def find_next_activity(ctx, deal_activity:, **)
    deal_investor = deal_activity.deal_investor
    return true if deal_investor.nil? || !deal_activity.Complete?

    ctx[:next_activity] = deal_investor.deal_activities
                                       .where(status: ["incomplete", "template", nil])
                                       .where("sequence > ?", deal_activity.sequence)
                                       .first
    true
  end

  def perform_next_action!(ctx, deal_activity:, next_activity: nil, **)
    return true if next_activity.nil?

    deal_investor = deal_activity.deal_investor
    is_current_step = deal_investor.deal_activity_id == deal_activity.template_id

    if is_current_step
      # FULL TRANSITION: Move investor + Generate tasks + Broadcast
      PerformActivityAction.call(
        deal_investor: deal_investor,
        deal_activity: deal_activity,
        initial_deal_activity_id: deal_investor.deal_activity.id,
        target_deal_activity_id: next_activity.id,
        user_id: ctx[:user_id]
      )
    else
      # PARTIAL ACTION: Just generate tasks for the next step relative to this one
      GenerateDealStepTasksJob.perform_later(deal_investor.id, ctx[:user_id], next_activity.id)
    end
    true
  end
end
