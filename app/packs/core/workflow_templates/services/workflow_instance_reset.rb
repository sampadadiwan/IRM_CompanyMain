# Resets an active instance back to step 1, archiving all actor responses.
# Step-1 actors are re-notified so they know to re-vote from scratch.
class WorkflowInstanceReset < Trailblazer::Operation
  step :check_active,    Output(:failure) => End(:not_active)
  step :check_has_steps, Output(:failure) => End(:no_steps)
  step :reset_instance
  step :notify_first_step_actors

  def check_active(ctx, instance:, **)
    return true if instance.instance_active?

    ctx[:errors] = "Only active instances can be reset."
    false
  end

  def check_has_steps(ctx, instance:, **)
    ctx[:first_pos] = instance.snapshot_steps.first&.dig(:position).to_i
    return true if ctx[:first_pos] && !ctx[:first_pos].zero?

    ctx[:errors] = "Cannot reset: this workflow has no steps in its snapshot."
    false
  end

  def reset_instance(ctx, instance:, **)
    ActiveRecord::Base.transaction do
      # Archive ALL active responses across every step — the whole run is wiped
      instance.workflow_actor_responses.active.update_all(archived: true)
      instance.update!(current_step_position: ctx[:first_pos], status: :active)

      # Audit entry using to_state "reset" so the view can exclude it from the
      # resolved-state display while keeping it visible in the full audit trail
      WorkflowStateChange.create!(
        workflow_instance: instance,
        step_position:     ctx[:first_pos],
        from_state:        nil,
        to_state:          "reset",
        note:              "Workflow reset to step 1",
        channel:           :ui
      )
    end
    true
  end

  # Notify first-step actors after reset_instance's transaction commits (same pattern as launch)
  def notify_first_step_actors(ctx, instance:, **)
    WorkflowStepActorNotifier.call(instance: instance, step_position: ctx[:first_pos])
    true
  end
end
