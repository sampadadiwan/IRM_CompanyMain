# Fires an ARMED obligation (event-triggered / ongoing — e.g. "notify LP within
# 5 business days of a key person event"): the user supplies the deadline and a
# dated task is created on the spot. MVP keeps the trigger decision human;
# automatic firing from platform events is deferred by design.
class ObligationFire < Trailblazer::Operation
  step :validate_armed
  step :create_task
  left :handle_errors

  def validate_armed(ctx, obligation:, due_date:, **)
    if due_date.blank?
      ctx[:error] = "A due date is required to fire an obligation"
      return false
    end
    return true if obligation.armed?

    ctx[:error] = "Only approved event-triggered obligations can be fired"
    false
  end

  def create_task(ctx, obligation:, due_date:, user: nil, **)
    ctx[:task] = Task.create!(
      details: "#{obligation.title} — #{obligation.side_letter.investor.investor_name} (#{obligation.source_clause.presence || 'side letter'})",
      category: "Compliance",
      owner: obligation,
      assigned_to_id: obligation.owner_user_id,
      entity_id: obligation.entity_id,
      for_entity_id: obligation.entity_id,
      user: user,
      due_date: due_date
    )
    true
  end

  def handle_errors(ctx, **)
    Rails.logger.warn("[ObligationFire] #{ctx[:error]}")
    false
  end
end
