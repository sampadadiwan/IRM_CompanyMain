# Launches a new workflow instance for any workflowable object (Folder, Document, etc.).
class WorkflowInstanceLaunch < Trailblazer::Operation
  step :check_template_assigned, Output(:failure) => End(:no_template)
  step :create_instance,         Output(:failure) => End(:already_active)
  step :notify_first_step_actors

  # The backstop for every launch path (the launch modal, a rule's auto_launch, KpiReport's
  # per-period launch): a disabled template never starts a new workflow, however the launch was
  # triggered. Checked here as well as at each caller so a new caller cannot miss it.
  def check_template_assigned(ctx, workflowable:, **)
    template = workflowable.workflow_template

    if template.nil?
      ctx[:errors] = "This object has no workflow template assigned."
      return false
    end

    unless template.enabled?
      ctx[:errors] = "The template assigned to this object (\"#{template.name}\") is disabled, so no workflow was started."
      return false
    end

    true
  end

  def create_instance(ctx, workflowable:, launched_by:, **)
    # Worked examples H2 (launch never evaluates; lock without reloading the record) — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    # Lock the workflowable row to serialise concurrent launches — prevents two active instances.
    # Lock a separate copy rather than calling workflowable.lock!: lock! reloads the caller's object,
    # which wipes its saved_changes. Auto-launch runs inside the record's own create callbacks, so a
    # reload there broke callers that check saved_change_to_*? afterwards (e.g. CapitalCall's
    # remittance generation silently did nothing).
    ActiveRecord::Base.transaction do
      workflowable.class.lock.find(workflowable.id)
      if workflowable.workflow_instances.instance_active.exists?
        ctx[:errors] = "A workflow is already in progress for this object. Complete or archive it first."
        raise ActiveRecord::Rollback
      end

      assignment = workflowable.workflow_assignment
      template   = assignment.workflow_template
      snapshot   = build_snapshot(template)
      ctx[:instance] = WorkflowInstance.create!(
        workflowable:          workflowable,
        workflow_assignment:   assignment,
        workflow_template:     template,
        entity_id:             workflowable.entity_id,
        launched_by:           launched_by,
        template_snapshot:     snapshot,
        current_step_position: first_step_position(template),
        status:                :active,
        # Evaluated from data when any step is system/acknowledge. Launch itself never evaluates:
        # auto-launch runs inside the record's create transaction, and the first evaluation is
        # the next page view or 15-minute tick.
        evaluated:             snapshot[:steps].any? { |step| step[:kind].to_s != "human" }
      )
    end
    ctx[:instance].present?
  end

  # Notify first-step actors after create_instance's transaction commits so a mailer
  # failure does not roll back the newly created instance.
  def notify_first_step_actors(ctx, **)
    instance = ctx[:instance]
    # A system/acknowledge first step has no actors to email; the evaluator emails approvers when
    # a human step later becomes current
    return true unless instance.current_step_data.to_h[:kind].to_s.in?(["", "human"])

    WorkflowStepActorNotifier.call(instance:, step_position: instance.current_step_position)
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
      # includes: one query for every step's actors (actor_ids below) instead of one per step
      steps: template.workflow_steps.order(:position).includes(:workflow_step_actors).map { |step|
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
          actor_ids:              step.workflow_step_actors.map(&:user_id),
          # Journey fields (capital-call-journey). Check keys are snapshotted, their logic is not:
          # a key's meaning never changes (WorkflowChecks::Registry), so this stays stable.
          kind:                   step.kind,
          check_key:              step.check_key,
          skip_key:               step.skip_key,
          owner_user_id:          step.owner_user_id,
          unlocks:                step.unlocks,
          keep_on_regress:        step.keep_on_regress
        }
      }
    }
  end
end
