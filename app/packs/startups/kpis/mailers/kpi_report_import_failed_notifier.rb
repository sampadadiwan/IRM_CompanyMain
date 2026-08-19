# Sent to fund employees when a portco's submitted workbook could not be imported (blocking errors
# after the submit gate — rare: S3 hiccup, file changed, mapping edited between check and import).
# The report has been reopened (draft_saved) so the portco can fix and resubmit.
class KpiReportImportFailedNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    KpiReportsMailer
  end

  def email_method(_notification = nil)
    :import_failed_notification
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
      "KPI import failed for #{record.portfolio_company.investor_name} (#{I18n.l(record.as_of)}) — report reopened for the portco"
    end

    def url
      kpi_report_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
