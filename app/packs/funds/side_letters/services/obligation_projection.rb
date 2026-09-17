# Projects an APPROVED obligation into the task system:
#   - recurring (calendar_event + RRULE)  -> TaskRecurrenceRule; the nightly
#     RecurringTaskGeneratorJob materializes the actual Task occurrences
#   - dated one-off (one_time, or calendar_event without an RRULE but with a
#     next_due_date)                      -> a single Task
#   - event-triggered / ongoing           -> nothing; the obligation stays armed
#
# Idempotent: re-calling for an obligation that already has its projection is a
# no-op, so approve can be retried safely.
class ObligationProjection < Trailblazer::Operation
  step :validate_approved
  step :project
  left :handle_errors

  def validate_approved(ctx, obligation:, **)
    return true if obligation.approved?

    ctx[:error] = "Only approved obligations can be projected"
    false
  end

  # Projects based on shape: recurring → recurrence rule, dated → single task,
  # undated → armed (manual Fire). Any obligation with a concrete next_due_date
  # gets a task regardless of trigger_type — armed is only for obligations
  # where the deadline is genuinely unknown until an event occurs.
  def project(ctx, obligation:, **)
    if obligation.recurring?
      project_recurring(ctx, obligation)
    elsif obligation.next_due_date.present?
      project_one_time(ctx, obligation)
    else
      ctx[:projected] = :none
      true
    end
  end

  def handle_errors(ctx, **)
    Rails.logger.error("[ObligationProjection] #{ctx[:error]}")
    false
  end

  private

  def project_recurring(ctx, obligation)
    # Already projected (approve retried) — nothing to do
    return ctx[:projected] = :existing_rule if obligation.task_recurrence_rule_id.present?

    rule = TaskRecurrenceRule.create!(
      entity_id: obligation.entity_id,
      rrule: obligation.frequency_rrule,
      # First occurrence lands on the obligation's next due date
      start_date: obligation.next_due_date || Time.zone.today,
      task_template_payload: task_payload(obligation)
    )
    obligation.update!(task_recurrence_rule: rule)
    ctx[:projected] = :recurrence_rule
    true
  end

  def project_one_time(ctx, obligation)
    return ctx[:projected] = :existing_task if obligation.tasks.exists?

    task = Task.new(task_payload(obligation).merge("due_date" => obligation.next_due_date))
    # Alerts for obligations come from the enforcement run, not task creation
    task.send_notification_flag = false
    task.save!
    ctx[:projected] = :task
    true
  end

  # Merged verbatim into Task.create! both here and by RecurringTaskGeneratorJob,
  # so keys must be valid Task attributes (string keys per the generator).
  def task_payload(obligation)
    {
      "details" => obligation_task_details(obligation),
      "category" => task_category_for(obligation),
      "owner_type" => "SideLetterObligation",
      "owner_id" => obligation.id,
      "assigned_to_id" => obligation.owner_user_id,
      "entity_id" => obligation.entity_id,
      "for_entity_id" => obligation.entity_id
    }
  end

  # @return [String] Task category derived from the obligation's legal classification.
  #   CP and CS get their own categories so task boards can separate them visually;
  #   standard SLOs (and nil) fall back to the original "Compliance" bucket.
  def task_category_for(obligation)
    case obligation.legal_category
    when "condition_precedent"  then "Condition Precedent"
    when "condition_subsequent" then "Condition Subsequent"
    else "Compliance"
    end
  end

  # @return [String] Human-readable task description line. Portfolio investment
  #   obligations reference the portfolio company; commitment obligations reference
  #   the side letter investor.
  def obligation_task_details(obligation)
    source_label = if obligation.sourceable_type == "PortfolioInvestment"
                     obligation.sourceable&.portfolio_company&.investor_name || "Portfolio Investment"
                   else
                     obligation.side_letter&.investor&.investor_name || "Side Letter"
                   end
    "#{obligation.title} — #{source_label} (#{obligation.source_clause.presence || 'side letter'})"
  end
end
