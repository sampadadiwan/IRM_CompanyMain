class WorkflowStepActorNotifier < Trailblazer::Operation
  # Sends step_activation emails to every actor assigned to the given step position.
  # Enqueued after the caller's transaction commits so a delivery failure is non-fatal.
  # Steps with notify_on_activation: false (e.g. a bulk auto-assignment step) are skipped
  # entirely, so importing many workflowables at once doesn't slam actors with emails.
  step :notify

  def notify(_ctx, instance:, step_position:, **)
    step = instance.snapshot_steps.find { |s| s[:position].to_i == step_position }
    return true unless step
    return true unless step[:notify_on_activation]

    Array(step[:actor_ids]).each do |actor_id|
      actor = User.find_by(id: actor_id)
      next unless actor

      WorkflowMailer.with(
        user_id:       actor.id,
        entity_id:     instance.entity_id,
        instance_id:   instance.id,
        step_position: step_position
      ).step_activation.deliver_later
    end
    true
  end
end
