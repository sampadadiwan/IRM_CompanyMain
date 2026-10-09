# Service to send a manual notification reminder for a KPI report.
# This ensures the report is enabled for self-reporting and triggers notifications.
class SendPortcoNotification < Trailblazer::Operation
  step :enable_self_reporting
  step :notify_users
  step :start_journey

  # Ensure the report has self-reporting enabled and advance status to link_sent.
  def enable_self_reporting(_ctx, model:, **)
    model.enable_portco_upload = true unless model.enable_portco_upload?
    # Only advance if not already submitted — never regress a completed report.
    unless model.status_submitted? || model.status_reviewed?
      model.status = 'link_sent'
      model.link_sent_at = Time.current
    end
    model.save!
    true
  end

  # Trigger notifications for all users associated with the portfolio company.
  # This uses the KpiReportNotifier to send emails.
  def notify_users(_ctx, model:, entity_id:, **)
    model.portfolio_company.notification_users(model, with_tag: 'Kpi').each do |user|
      KpiReportNotifier.with(record: model, entity_id: entity_id).deliver_later(user)
    end
  end

  # Asking a portco for a period makes the report a request — including a report an earlier import
  # created for that period — so it gets the KPI report journey; one that has it moves on.
  # Worked examples E18 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def start_journey(_ctx, model:, **)
    model.start_journey!
    model.journey_progress!
    true
  end
end
