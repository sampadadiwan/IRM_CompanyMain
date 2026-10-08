# "KPIs for <portco> — <date> are complete": sent by KpiReportCompletionEmail when someone clicks Send
# completion email on a KPI report whose journey has that step.
# Worked examples H8 — openspec/changes/kpi-report-journey/design.md#worked-examples
class KpiReportCompletedNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    KpiReportsMailer
  end

  def email_method(_notification = nil)
    :completed_notification
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      kpi_report_id: record.id,
      entity_id: params[:entity_id]
    }
  end

  notification_methods do
    def message
      "KPIs for #{record.for_name} — #{I18n.l(record.as_of, format: :email, locale: :en)} are complete"
    end

    def url
      kpi_report_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
