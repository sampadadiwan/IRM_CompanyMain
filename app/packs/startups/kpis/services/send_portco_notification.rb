# Service to send a manual notification reminder for a KPI report.
# This ensures the report is enabled for self-reporting and triggers notifications.
class SendPortcoNotification < Trailblazer::Operation
  step :enable_self_reporting
  step :notify_users

  # Ensure the report has self-reporting enabled.
  # This flag allows portfolio companies to access the report.
  def enable_self_reporting(_ctx, model:, **)
    model.enable_portco_upload = true
    model.save!
  end

  # Trigger notifications for all users associated with the portfolio company.
  # This uses the KpiReportNotifier to send emails.
  def notify_users(_ctx, model:, entity_id:, **)
    model.portfolio_company.notification_users(model).each do |user|
      KpiReportNotifier.with(record: model, entity_id: entity_id).deliver_later(user)
    end
  end
end
