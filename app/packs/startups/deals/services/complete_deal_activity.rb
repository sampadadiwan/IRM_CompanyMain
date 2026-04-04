class CompleteDealActivity < Trailblazer::Operation
  step :save_activity!
  step :check_if_current_step?
  step :perform_next_action!

  private

  def save_activity!(_ctx, deal_activity:, params:, **)
    deal_activity.assign_attributes(params)
    deal_activity.save
  end

  # Check if the activity being completed is the one the investor is currently on
  def check_if_current_step?(ctx, deal_activity:, **)
    deal_investor = deal_activity.deal_investor
    return true if deal_investor.nil?

    # Only advance if the activity status was changed to 'Complete'
    # AND it's currently the investor's active step
    ctx[:is_current_step] = deal_activity.Complete? &&
                            deal_investor.deal_activity_id == deal_activity.template_id
    true
  end

  def perform_next_action!(ctx, deal_activity:, is_current_step:, **)
    return true unless is_current_step

    deal_investor = deal_activity.deal_investor
    # Find the next incomplete activity
    next_activity = deal_investor.deal_activities
                                 .where(status: ["incomplete", "template", nil])
                                 .where("sequence > ?", deal_activity.sequence)
                                 .first

    return true if next_activity.nil?

    # Trigger the transition to the next step
    # This will handle step update, task generation, and broadcasts
    PerformActivityAction.call(
      deal_investor: deal_investor,
      deal_activity: deal_activity, # The one just marked complete
      initial_deal_activity_id: deal_investor.deal_activity.id,
      target_deal_activity_id: next_activity.id,
      user_id: ctx[:user_id]
    )
  end
end
