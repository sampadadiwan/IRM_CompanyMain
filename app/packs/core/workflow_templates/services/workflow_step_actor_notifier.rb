class WorkflowStepActorNotifier < Trailblazer::Operation
  # Sends step_activation emails to every actor assigned to the given step position.
  # Enqueued after the caller's transaction commits so a delivery failure is non-fatal.
  # Steps with notify_on_activation: false (e.g. a bulk auto-assignment step) are skipped
  # entirely, so importing many workflowables at once doesn't slam actors with emails.
  # except_user_id: the person whose action made this step current — they are already on the page.
  step :notify

  def notify(_ctx, instance:, step_position:, except_user_id: nil, **)
    step = instance.snapshot_steps.find { |s| s[:position].to_i == step_position }
    return true unless step
    return true unless step[:notify_on_activation]

    Array(step[:actor_ids]).each do |actor_id|
      next if except_user_id && actor_id.to_i == except_user_id

      actor = User.find_by(id: actor_id)
      next unless actor

      # Through the notifier: logged, honours the template's email/WhatsApp switches
      WorkflowNotifier.with(record: instance, entity_id: instance.entity_id,
                            email_method: :step_activation, step_position:).deliver_later(actor)
    end
    true
  end
end
