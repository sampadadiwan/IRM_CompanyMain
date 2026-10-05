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

  # The owner to remind for a step, or nil when there is none or they are no longer active.
  # Read from the live template step first, so fixing an owner in the template fixes in-flight
  # journeys (design Decision 18).
  def self.owner_for(instance, step_data)
    live_step = instance.workflow_template&.workflow_steps&.find_by(position: step_data[:position].to_i)
    owner_id = live_step ? live_step.owner_user_id : step_data[:owner_user_id]
    owner = owner_id ? User.find_by(id: owner_id) : instance.workflowable.workflow_default_owner
    owner if owner&.active
  end

  private

  def send_reminders_for(instance)
    # Journeys: bring the instance up to date from the data first, so nobody is reminded about a
    # step that is already done, then remind the right person for the step's kind
    if instance.evaluated
      WorkflowEvaluator.call(instance:, cause: :progress)
      instance.reload
      return unless instance.instance_active?
    end

    step_data = instance.current_step_data
    return unless step_data
    return send_owner_reminder(instance, step_data) if instance.evaluated && step_data[:kind].to_s.in?(%w[system acknowledge])

    interval = effective_interval(instance, step_data)
    return unless interval

    # Use the instance's updated_at as the step-start reference for the first cycle;
    # subsequent cycles use the most recent auto_reminder state-change timestamp.
    last_reminder_at = instance.workflow_state_changes
                                .where(step_position: instance.current_step_position,
                                       channel: :auto_reminder)
                                .maximum(:created_at)
    # Journeys time reminders from when the step became current (stamped from the data);
    # instance.updated_at moves on every evaluation so it can't be used for them
    reference_time = if instance.evaluated
                       [last_reminder_at, instance.current_step_since].compact.max || instance.updated_at
                     else
                       last_reminder_at || instance.updated_at
                     end
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

      WorkflowNotifier.with(record: instance, entity_id: instance.entity_id, # denormalized — no folder join needed
                            email_method: :reminder, step_position: instance.current_step_position).deliver_later(actor)

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

  # Worked examples H9, H15, E16, X4 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def send_owner_reminder(instance, step_data)
    interval = effective_interval(instance, step_data)
    return unless interval

    position = instance.current_step_position
    last_reminder_at = instance.workflow_state_changes.where(step_position: position, to_state: "owner_reminded")
                               .maximum(:created_at)
    reference_time = [last_reminder_at, instance.current_step_since].compact.max || instance.updated_at
    return unless reference_time < interval.days.ago

    owner = self.class.owner_for(instance, step_data)
    return unless owner # the panel shows "Owner unavailable — update the journey template"

    message = instance.step_result(position)&.dig("message")
    WorkflowNotifier.with(record: instance, entity_id: instance.entity_id, email_method: :owner_reminder,
                          step_position: position, message:).deliver_later(owner)
    WorkflowStateChange.create!(workflow_instance: instance, step_position: position, actor: owner,
                                to_state: "owner_reminded", note: message, channel: :auto_reminder)
  end

  # Returns the effective reminder interval for this step in days, or nil to skip.
  # The snapshot already stores the pre-resolved value (step override → template default → nil).
  # 0 or nil means disabled; any positive integer is the interval.
  def effective_interval(_instance, step_data)
    interval = step_data[:reminder_interval_days]
    interval.to_i.positive? ? interval.to_i : nil
  end
end
