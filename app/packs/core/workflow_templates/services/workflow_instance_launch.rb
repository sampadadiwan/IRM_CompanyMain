# Launches a new workflow instance for any workflowable object (Folder, Document, etc.).
class WorkflowInstanceLaunch < Trailblazer::Operation
  step :check_template_assigned, Output(:failure) => End(:no_template)
  step :create_instance,         Output(:failure) => End(:already_active)
  step :notify_first_step_actors

  def check_template_assigned(ctx, workflowable:, **)
    return true if workflowable.workflow_template

    ctx[:errors] = "This object has no workflow template assigned."
    false
  end

  def create_instance(ctx, workflowable:, launched_by:, **)
    # Lock the workflowable row to serialise concurrent launches — prevents two active instances
    ActiveRecord::Base.transaction do
      workflowable.lock!
      if workflowable.workflow_instances.instance_active.exists?
        ctx[:errors] = "A workflow is already in progress for this object. Complete or archive it first."
        raise ActiveRecord::Rollback
      end

      assignment = workflowable.workflow_assignment
      template   = assignment.workflow_template
      ctx[:instance] = WorkflowInstance.create!(
        workflowable:          workflowable,
        workflow_assignment:   assignment,
        workflow_template:     template,
        entity_id:             workflowable.entity_id,
        launched_by:           launched_by,
        template_snapshot:     build_snapshot(template),
        current_step_position: first_step_position(template),
        status:                :active
      )
    end
    ctx[:instance].present?
  end

  # Notify first-step actors after create_instance's transaction commits so a mailer
  # failure does not roll back the newly created instance.
  def notify_first_step_actors(ctx, **)
    WorkflowStepActorNotifier.call(instance: ctx[:instance], step_position: ctx[:instance].current_step_position)
    true
  end

  private

  def first_step_position(template)
    template.workflow_steps.minimum(:position) || 1
  end

  # Snapshots the template + all steps + actors at launch time so live edits
  # to the template do not affect this in-flight instance.
  def build_snapshot(template)
    {
      id:                       template.id,
      name:                     template.name,
      description:              template.description,
      reminder_interval_days:   template.reminder_interval_days,
      attach_document_in_email: template.attach_document_in_email,
      steps: template.workflow_steps.order(:position).map { |step|
        {
          position:               step.position,
          name:                   step.name,
          description:            step.description,
          states:                 step.states,
          quorum_rule:            step.quorum_rule,
          on_reject_rule:         step.on_reject_rule,
          on_reject_target_step:  step.on_reject_target_step,
          reminder_interval_days: step.effective_reminder_interval,
          notify_on_activation:   step.notify_on_activation,
          actor_ids:              step.workflow_step_actors.map(&:user_id)
        }
      }
    }
  end
end
