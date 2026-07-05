class WorkflowAdvancer < Trailblazer::Operation
  # Applies a resolved state to the current step: records the state change event,
  # then advances, rejects, reverts, or restarts the instance per the on_reject_rule.
  # `actor` may be nil for system-triggered advances.
  # IMPORTANT: callers must NOT wrap this operation in their own ActiveRecord::Base.transaction.
  # advance_step acquires its own row-level lock and fires step-activation emails after its
  # transaction commits. Wrapping it in an outer transaction would turn that into a savepoint,
  # causing deliver_later jobs to be enqueued before the outer transaction commits.
  step :guard_active
  step :advance_step, Output(:failure) => End(:stale)
  step :notify_if_moved

  def guard_active(ctx, instance:, **)
    instance.reload
    ctx[:current_pos] = instance.current_step_position
    instance.instance_active?
  end

  # Returns false (routing to End(:stale), skipping notify_if_moved) when a concurrent
  # advance() already moved this step — mirrors the original method's early `return`,
  # which skipped notification entirely for the losing caller.
  def advance_step(ctx, instance:, resolved_state:, actor: nil, note: nil, channel: :ui, **)
    step_data   = instance.current_step_data
    current_pos = ctx[:current_pos]
    steps       = instance.snapshot_steps
    advanced    = false

    ActiveRecord::Base.transaction do
      # Acquire a row-level lock here so concurrent advance() calls (e.g. two actors
      # responding to an any_one step whose responses were committed by separate outer
      # transactions) are serialised. The second caller reloads after the lock and bails
      # out if the step already moved on (guard below).
      instance.lock!
      instance.reload
      # Another concurrent advance() already moved the step — nothing to do.
      next unless instance.instance_active? && instance.current_step_position == current_pos

      WorkflowStateChange.create!(
        workflow_instance: instance,
        step_position:     current_pos,
        actor:             actor,
        from_state:        nil,
        to_state:          resolved_state,
        note:              note,
        channel:           channel
      )

      if passing_state?(step_data, resolved_state)
        advance_to_next(instance, steps, current_pos)
      else
        handle_rejection(instance, step_data, steps, current_pos)
      end
      advanced = true
    end

    advanced
  end

  # Notification fires here — after advance_step's transaction commits — so jobs
  # are never orphaned by an uncommitted transaction.
  def notify_if_moved(ctx, instance:, **)
    instance.reload
    new_pos = instance.current_step_position
    if instance.instance_active? && new_pos != ctx[:current_pos]
      WorkflowStepActorNotifier.call(instance: instance, step_position: new_pos)
    end
    true
  end

  private

  # The first state in the CSV list is the passing state; all others trigger on_reject_rule.
  def passing_state?(step_data, resolved_state)
    first_state = step_data[:states].to_s.split(",").first&.strip
    resolved_state.to_s.strip == first_state
  end

  def advance_to_next(instance, steps, current_pos)
    next_step = steps.find { |s| s[:position].to_i > current_pos }
    if next_step
      instance.update!(current_step_position: next_step[:position].to_i)
    else
      instance.update!(status: :complete)
    end
  end

  def handle_rejection(instance, step_data, steps, current_pos)
    on_reject_rule = step_data[:on_reject_rule].to_s

    case on_reject_rule
    when "stop"
      instance.update!(status: :rejected)

    when "previous_step"
      prev_step = steps.select { |s| s[:position].to_i < current_pos }.last
      if prev_step
        archive_step_responses(instance, current_pos)
        instance.update!(current_step_position: prev_step[:position].to_i)
      else
        # Already at first step — stop the workflow
        instance.update!(status: :rejected)
      end

    when "restart"
      # Archive every active response so actors re-vote from scratch at step 1
      instance.workflow_actor_responses.active.update_all(archived: true)
      first_pos = steps.first[:position].to_i
      instance.update!(current_step_position: first_pos)

    when "go_to_step_n"
      target_pos = step_data[:on_reject_target_step].to_i
      target     = steps.find { |s| s[:position].to_i == target_pos }
      if target
        archive_step_responses(instance, current_pos)
        instance.update!(current_step_position: target_pos)
      else
        instance.update!(status: :rejected)
      end

    else
      instance.update!(status: :rejected)
    end
  end

  # Archives responses only for the given step (used on revert / go_to_step_n)
  def archive_step_responses(instance, step_position)
    instance.workflow_actor_responses
            .active
            .for_step(step_position)
            .update_all(archived: true)
  end
end
