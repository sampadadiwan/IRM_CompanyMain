class WorkflowInstanceService
  # Launches a new workflow instance for any workflowable object (Folder, Document, etc.).
  # Raises ArgumentError if the object has no template assigned or already has an active instance.
  def self.launch(workflowable, launched_by:)
    raise ArgumentError, "This object has no workflow template assigned." unless workflowable.workflow_template

    # Lock the workflowable row to serialise concurrent launches — prevents two active instances
    ActiveRecord::Base.transaction do
      workflowable.lock!
      if workflowable.workflow_instances.instance_active.exists?
        raise ArgumentError, "A workflow is already in progress for this object. Complete or archive it first."
      end

      assignment = workflowable.workflow_assignment
      template   = assignment.workflow_template
      instance   = WorkflowInstance.create!(
        workflowable:        workflowable,
        workflow_assignment:  assignment,
        workflow_template:    template,
        entity_id:            workflowable.entity_id,
        launched_by:          launched_by,
        template_snapshot:    build_snapshot(template),
        current_step_position: first_step_position(template),
        status:               :active
      )
      # Notify first-step actors outside the transaction so a mailer failure
      # does not roll back the newly created instance
      instance
    end.tap { |inst| notify_step_actors(inst, inst.current_step_position) }
  end

  # Resets an active instance back to step 1, archiving all actor responses.
  # Step-1 actors are re-notified so they know to re-vote from scratch.
  def self.reset(instance)
    raise ArgumentError, "Only active instances can be reset." unless instance.instance_active?

    first_pos = instance.snapshot_steps.first&.dig(:position).to_i
    raise ArgumentError, "Cannot reset: this workflow has no steps in its snapshot." if first_pos.zero?

    ActiveRecord::Base.transaction do
      # Archive ALL active responses across every step — the whole run is wiped
      instance.workflow_actor_responses.active.update_all(archived: true)
      instance.update!(current_step_position: first_pos, status: :active)

      # Audit entry using to_state "reset" so the view can exclude it from the
      # resolved-state display while keeping it visible in the full audit trail
      WorkflowStateChange.create!(
        workflow_instance: instance,
        step_position:     first_pos,
        from_state:        nil,
        to_state:          "reset",
        note:              "Workflow reset to step 1",
        channel:           :ui
      )
    end

    # Notify first-step actors outside the transaction (same pattern as launch)
    notify_step_actors(instance, first_pos)
  end

  private

  # Sends step_activation emails to every actor assigned to the given step position.
  # Enqueued after the transaction commits so a delivery failure is non-fatal.
  def self.notify_step_actors(instance, step_position)
    step = instance.snapshot_steps.find { |s| s[:position].to_i == step_position }
    return unless step

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
  end

  def self.first_step_position(template)
    template.workflow_steps.minimum(:position) || 1
  end

  # Snapshots the template + all steps + actors at launch time so live edits
  # to the template do not affect this in-flight instance.
  def self.build_snapshot(template)
    {
      id:                      template.id,
      name:                    template.name,
      description:             template.description,
      reminder_interval_days:  template.reminder_interval_days,
      attach_document_in_email: template.attach_document_in_email,
      steps: template.workflow_steps.order(:position).map { |step|
        {
          position:              step.position,
          name:                  step.name,
          description:           step.description,
          states:                step.states,
          quorum_rule:           step.quorum_rule,
          on_reject_rule:        step.on_reject_rule,
          on_reject_target_step: step.on_reject_target_step,
          reminder_interval_days: step.effective_reminder_interval,
          actor_ids:             step.workflow_step_actors.map(&:user_id)
        }
      }
    }
  end
end
