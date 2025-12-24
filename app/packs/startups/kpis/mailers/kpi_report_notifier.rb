class KpiReportNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    KpiReportsMailer
  end

  def email_method(_notification = nil)
    :send_reminder
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
      "Reminder to report KPIs for #{record.for_name} - #{record.as_of}"
    end

    def url
      kpi_report_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
