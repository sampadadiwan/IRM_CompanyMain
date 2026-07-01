class WorkflowAutoReminderJob < ApplicationJob
  queue_as :default

  # Runs daily. Iterates every active WorkflowInstance and sends reminder emails
  # to all pending actors whose step has been idle for longer than the effective
  # reminder_interval_days (step override → template default → skip if nil).
  def perform
    WorkflowInstance.instance_active.find_each do |instance|
      send_reminders_for(instance)
    rescue StandardError => e
      # Log and continue so one bad instance does not abort the whole run
      Rails.logger.error(
        "[WorkflowAutoReminderJob] instance #{instance.id}: #{e.class} – #{e.message}"
      )
    end
  end

  private

  def send_reminders_for(instance)
    step_data = instance.current_step_data
    return unless step_data

    interval = effective_interval(instance, step_data)
    return unless interval

    # Use the instance's updated_at as the step-start reference for the first cycle;
    # subsequent cycles use the most recent auto_reminder state-change timestamp.
    last_reminder_at = instance.workflow_state_changes
                                .where(step_position: instance.current_step_position,
                                       channel: :auto_reminder)
                                .maximum(:created_at)
    reference_time = last_reminder_at || instance.updated_at
    return unless reference_time < interval.days.ago

    # Actors who still haven't submitted a response for this step
    responded_ids = instance.workflow_actor_responses
                            .active
                            .for_step(instance.current_step_position)
                            .pluck(:actor_id)
    pending_ids = Array(step_data[:actor_ids]).map(&:to_i) - responded_ids
    return if pending_ids.empty?

    pending_ids.each do |actor_id|
      actor = User.find_by(id: actor_id)
      next unless actor

      WorkflowMailer.with(
        user_id:       actor.id,
        entity_id:     instance.entity_id,  # denormalized — no folder join needed
        instance_id:   instance.id,
        step_position: instance.current_step_position
      ).reminder.deliver_later

      # Record the dispatch so the next job run can calculate from this timestamp
      WorkflowStateChange.create!(
        workflow_instance: instance,
        step_position:     instance.current_step_position,
        actor:             actor,
        from_state:        nil,
        to_state:          "reminder_sent",
        note:              "Auto-reminder dispatched",
        channel:           :auto_reminder
      )
    end
  end

  # Returns the effective reminder interval for this step in days, or nil to skip.
  # The snapshot already stores the pre-resolved value (step override → template default → nil).
  # 0 or nil means disabled; any positive integer is the interval.
  def effective_interval(_instance, step_data)
    interval = step_data[:reminder_interval_days]
    interval.to_i.positive? ? interval.to_i : nil
  end
end
