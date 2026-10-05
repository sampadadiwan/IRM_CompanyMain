# Records a "Mark reviewed" confirmation on the current acknowledge step, then evaluates so the
# journey moves on. Authorisation (update rights on the record) is checked by the controller.
# Worked examples H4, X3 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
class WorkflowAcknowledge < Trailblazer::Operation
  step :check_step
  step :record_confirmation
  step :evaluate

  def check_step(ctx, instance:, step_position:, **)
    step = instance.snapshot_steps.find { |s| s[:position].to_i == step_position.to_i }
    if instance.evaluated && step && step[:kind].to_s == "acknowledge" &&
       instance.current_step_position == step_position.to_i && instance.instance_active?
      ctx[:step] = step
      return true
    end

    ctx[:errors] = "This step is not waiting for a review."
    false
  end

  def record_confirmation(ctx, instance:, step_position:, user:, **)
    ctx[:response] = WorkflowActorResponse.create!(
      workflow_instance: instance, actor: user, step_position: step_position.to_i,
      state: WorkflowStep::ACKNOWLEDGE_STATES, channel: :ui, responded_at: Time.current
    )
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    ctx[:errors] = "This step has already been reviewed."
    false
  end

  def evaluate(ctx, instance:, user:, **)
    ctx[:results] = WorkflowEvaluator.call(instance:, actor: user)[:results]
    true
  end
end
