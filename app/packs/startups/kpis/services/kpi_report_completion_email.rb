# Send completion email (KpiReportsController#send_completion_email): tells the people who need to
# know that this portfolio company's period is done — the portfolio company's manager, else the
# "Send completion email" step's actors, else every employee tagged Kpi (WorkflowAutoReminderJob.owners_for).
#
# Sends once: the report row is locked while completion_notified_at is checked and set, so a double
# click or two tabs send one email. The emails are queued after the lock is released.
# Returns ctx[:outcome] = :sent / :already_sent / :no_recipients, and ctx[:recipients].
# Worked examples H8, E10 — openspec/changes/kpi-report-journey/design.md#worked-examples
class KpiReportCompletionEmail < Trailblazer::Operation
  CHECK_KEY = "kpi_report.send_completion_email".freeze

  step :resolve_recipients
  step :claim
  step :deliver

  # The recipients, resolved like the journey's owners but using the step's actors (use: :actors)
  def resolve_recipients(ctx, kpi_report:, **)
    instance = kpi_report.current_workflow_instance
    step = instance&.snapshot_steps&.find { |s| s[:check_key] == CHECK_KEY }
    ctx[:recipients] = if instance && step
                         WorkflowAutoReminderJob.owners_for(instance, step, use: :actors)
                       else
                         # No step on this journey: same order without the step's actors
                         kpi_report.workflow_override_owners.select(&:active).presence ||
                           kpi_report.workflow_default_owners
                       end
    ctx[:outcome] = :no_recipients if ctx[:recipients].empty?
    true
  end

  # Claims the send under a row lock; nothing to send when it was already sent or nobody resolves
  def claim(ctx, kpi_report:, **)
    return true if ctx[:outcome] == :no_recipients

    kpi_report.with_lock do
      if kpi_report.completion_notified_at.present?
        ctx[:outcome] = :already_sent
      else
        kpi_report.update_columns(completion_notified_at: Time.current)
        ctx[:outcome] = :sent
      end
    end
    true
  end

  # After the lock: queue one email per recipient and move the journey on
  def deliver(ctx, kpi_report:, user:, **)
    return true unless ctx[:outcome] == :sent

    ctx[:recipients].each do |recipient|
      KpiReportCompletedNotifier.with(record: kpi_report, entity_id: kpi_report.entity_id).deliver_later(recipient)
    end
    kpi_report.journey_progress!(actor: user)
    true
  end
end
