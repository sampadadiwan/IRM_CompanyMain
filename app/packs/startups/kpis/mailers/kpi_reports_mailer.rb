class KpiReportsMailer < ApplicationMailer
  # Send a reminder email to a portfolio company user to report their KPIs.
  def send_reminder
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company

    subject = "#{@entity.name}: Reminder to report KPIs for #{@kpi_report.for_name} - #{@kpi_report.as_of}"
    send_mail(subject:)
  end

  def submitted_notification
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company
    subject = "KPIs submitted: #{@kpi_report.for_name} for #{I18n.l(@kpi_report.as_of)}"
    send_mail(subject:)
  end

  # A submitted workbook could not be imported (see KpiReportImportFailedNotifier).
  def import_failed_notification
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company
    @errors = Array(@kpi_report.validation_result&.dig('errors')).pluck('message')
    subject = "KPI import failed: #{@kpi_report.for_name} for #{I18n.l(@kpi_report.as_of)}"
    send_mail(subject:)
  end

  # The KPI report journey's completion email (KpiReportCompletedNotifier). The date in the subject uses
  # the email format with locale :en forced, as every email does (EmailDateLocalization).
  # Worked examples H8 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def completed_notification
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company
    subject = "KPIs for #{@kpi_report.for_name} — #{I18n.l(@kpi_report.as_of, format: :email, locale: :en)} are complete"
    send_mail(subject:)
  end

  def send_no_users_warning
    @portfolio_company = Investor.find(params[:portfolio_company_id])
    @kpi_report = KpiReport.find(params[:kpi_report_id])

    subject = "WARNING: No notification users found for #{@portfolio_company.investor_name}"
    mail(to: ENV.fetch("SUPPORT_EMAIL"), subject: subject)
  end
end
