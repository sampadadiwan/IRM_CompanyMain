class KpiReportSubmittedNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    KpiReportsMailer
  end

  def email_method(_notification = nil)
    :submitted_notification
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
      "KPIs submitted by #{record.portfolio_company.investor_name} for #{I18n.l(record.as_of)}"
    end

    def url
      kpi_report_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
