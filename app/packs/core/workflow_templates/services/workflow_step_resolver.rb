class WorkflowStepResolver
  # Evaluates the current step's quorum against active actor responses.
  # Returns one of:
  #   { resolved: "StateString" }  — quorum met, advance can be called
  #   { pending: true }            — waiting for more responses
  #   { tiebreaker: true }         — all responded but no consensus; admin must intervene
  def self.resolve(instance)
    step_data = instance.current_step_data
    return { pending: true } unless step_data

    actor_ids    = Array(step_data[:actor_ids]).map(&:to_i)
    quorum_rule  = step_data[:quorum_rule].to_s
    # Restrict all response queries to assigned actors — prevents non-actor rows
    # (injected directly or via future code paths) from affecting quorum counts
    responses    = instance.workflow_actor_responses
                           .active
                           .for_step(instance.current_step_position)
                           .where(actor_id: actor_ids)
    responded_ids = responses.map(&:actor_id)

    case quorum_rule
    when "any_one"
      first = responses.order(:responded_at).first
      first ? { resolved: first.state } : { pending: true }

    when "all"
      pending_ids = actor_ids - responded_ids
      return { pending: true } if pending_ids.any?

      states = responses.pluck(:state).uniq
      states.one? ? { resolved: states.first } : { tiebreaker: true }

    when "majority"
      total = actor_ids.size
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
  end
end
