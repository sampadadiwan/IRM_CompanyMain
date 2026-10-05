class WorkflowStepResolver < Trailblazer::Operation
  # Evaluates the current step's quorum against active actor responses.
  # ctx[:resolution] is set to one of:
  #   { resolved: "StateString" }  — quorum met, WorkflowAdvancer can be called
  #   { pending: true }            — waiting for more responses
  #   { tiebreaker: true }         — all responded but no consensus; admin must intervene
  step :resolve

  # step_position defaults to the current step; WorkflowEvaluator passes other positions to ask
  # whether an earlier human step's votes have resolved
  def resolve(ctx, instance:, step_position: nil, **)
    position  = (step_position || instance.current_step_position).to_i
    step_data = instance.snapshot_steps.find { |s| s[:position].to_i == position }
    unless step_data
      ctx[:resolution] = { pending: true }
      return true
    end

    actor_ids   = Array(step_data[:actor_ids]).map(&:to_i)
    quorum_rule = step_data[:quorum_rule].to_s
    # Restrict all response queries to assigned actors — prevents non-actor rows
    # (injected directly or via future code paths) from affecting quorum counts
    responses = instance.workflow_actor_responses
                        .active
                        .for_step(position)
                        .where(actor_id: actor_ids)
    responded_ids = responses.map(&:actor_id)

    ctx[:resolution] =
      case quorum_rule
      when "any_one"
        first = responses.order(:responded_at).first
        first ? { resolved: first.state } : { pending: true }

      when "all"
        pending_ids = actor_ids - responded_ids
        if pending_ids.any?
          { pending: true }
        else
          states = responses.pluck(:state).uniq
          states.one? ? { resolved: states.first } : { tiebreaker: true }
        end

      when "majority"
        total  = actor_ids.size
        counts = responses.group(:state).count
        # Check if any state already has a mathematical majority
        winner = counts.find { |_, c| c > total / 2.0 }
        if winner
          { resolved: winner[0] }
        elsif (actor_ids - responded_ids).empty?
          # All responded but no majority — tiebreaker
          { tiebreaker: true }
        else
          { pending: true }
        end

      else
        { pending: true }
      end

    true
  end
end
