class PerformActivityAction < Trailblazer::Operation
  step :validate_action_perform!
  step :mark_action_done!
  step :update_deal_investor
  step :notify_activity_move
  step :generate_step_tasks
  step :broadcast_changes

  private

  # Validates that the deal investor is currently on the expected step
  def validate_action_perform!(ctx, params: {}, deal_investor: nil, initial_deal_activity_id: nil, **)
    deal_investor ||= DealInvestor.find_by(id: params[:deal_investor_id])
    initial_id = initial_deal_activity_id || params[:initial_deal_activity_id]

    unless deal_investor.deal_activity.id.to_s == initial_id.to_s
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
  def update_deal_investor(ctx, deal_investor:, params: {}, target_deal_activity_id: nil, **)
    target_id = target_deal_activity_id || params[:target_deal_activity_id]
    target_deal_activity = DealActivity.find_by(id: target_id)

    # If it's an investor-specific activity, we want to store its template
    # so that deal_investor.deal_activity always points to the Template record.
    actual_activity = if target_deal_activity.deal_investor_id.present?
                        DealActivity.find_by(id: target_deal_activity.template_id)
                      else
                        target_deal_activity
                      end

    deal_investor.deal_activity = actual_activity
    deal_investor.save!
    ctx[:target_activity] = target_deal_activity
  end

  # Triggers notifications to employees and/or investors if configured for the new stage.
  def notify_activity_move(_ctx, deal_investor:, target_activity:, **)
    return true unless target_activity

    # Use the activity instance's flags to determine recipients
    if target_activity.notify_employees
      deal_investor.deal.entity.employees.active.company_admins.each do |admin|
        DealActivityMoveNotifier.with(
          record: deal_investor,
          entity_id: deal_investor.entity_id,
          activity_title: target_activity.title,
          email_method: "deal_activity_move"
        ).deliver_later(admin)
      end
    end

    if target_activity.notify_investor
      deal_investor.investor.notification_users(deal_investor.deal).each do |user|
        DealActivityMoveNotifier.with(
          record: deal_investor,
          entity_id: deal_investor.entity_id,
          activity_title: target_activity.title,
          email_method: "deal_activity_move"
        ).deliver_later(user)
      end
    end
    true
  end

  # Enqueues the job to generate tasks based on the new activity's tasks_csv field.
  # These tasks are assigned to the current user who performed the transition.
  def generate_step_tasks(ctx, deal_investor:, params: {}, target_deal_activity_id: nil, **)
    target_id = target_deal_activity_id || params[:target_deal_activity_id]
    GenerateDealStepTasksJob.perform_later(deal_investor.id, ctx[:current_user_id] || ctx[:user_id], target_id)
    true
  end

  def broadcast_changes(ctx, deal_activity:, **)
    ctx[:errors] = deal_activity.errors.full_messages
    deal_activity.deal.kanban_board.presence&.broadcast_board_event
    true
  end
end
