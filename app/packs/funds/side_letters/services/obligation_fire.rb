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

  # Creates a dated task from the fired obligation. Portfolio investment
  # obligations reference the portfolio company; commitment obligations
  # reference the side letter investor.
  def create_task(ctx, obligation:, due_date:, user: nil, **)
    source_label = if obligation.sourceable_type == "PortfolioInvestment"
                     obligation.sourceable&.portfolio_company&.investor_name || "Portfolio Investment"
                   else
                     obligation.side_letter&.investor&.investor_name || "Side Letter"
                   end
    ctx[:task] = Task.create!(
      details: "#{obligation.title} — #{source_label} (#{obligation.source_clause.presence || 'agreement'})",
      category: task_category_for(obligation),
      owner: obligation,
      assigned_to_id: obligation.owner_user_id,
      entity_id: obligation.entity_id,
      for_entity_id: obligation.entity_id,
      user: user,
      due_date: due_date
    )
    true
  end

  # @return [String] Task category based on legal classification
  def task_category_for(obligation)
    case obligation.legal_category
    when "condition_precedent"  then "Condition Precedent"
    when "condition_subsequent" then "Condition Subsequent"
    else "Compliance"
    end
  end

  def handle_errors(ctx, **)
    Rails.logger.warn("[ObligationFire] #{ctx[:error]}")
    false
  end
end
