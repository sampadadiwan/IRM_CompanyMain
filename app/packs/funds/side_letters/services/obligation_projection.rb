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

  def project(ctx, obligation:, **)
    if obligation.recurring?
      project_recurring(ctx, obligation)
    elsif obligation.next_due_date.present? && (obligation.trigger_one_time? || obligation.trigger_calendar_event?)
      project_one_time(ctx, obligation)
    else
      # Armed shape — visible in the matrix, fired manually via ObligationFire
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
      "details" => "#{obligation.title} — #{obligation.side_letter.investor.investor_name} (#{obligation.source_clause.presence || 'side letter'})",
      "category" => "Compliance",
      "owner_type" => "SideLetterObligation",
      "owner_id" => obligation.id,
      "assigned_to_id" => obligation.owner_user_id,
      "entity_id" => obligation.entity_id,
      "for_entity_id" => obligation.entity_id
    }
  end
end
