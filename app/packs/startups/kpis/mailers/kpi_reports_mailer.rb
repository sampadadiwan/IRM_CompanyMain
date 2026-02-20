class KpiReportsMailer < ApplicationMailer
  # Send a reminder email to a portfolio company user to report their KPIs.
  def send_reminder
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company

    subject = "Reminder to report KPIs for #{@kpi_report.for_name} - #{@kpi_report.as_of}"
    send_mail(subject:)
  end

  def send_no_users_warning
    @portfolio_company = Investor.find(params[:portfolio_company_id])
    @kpi_report = KpiReport.find(params[:kpi_report_id])

    subject = "WARNING: No notification users found for #{@portfolio_company.investor_name}"
    mail(to: ENV.fetch("SUPPORT_EMAIL"), subject: subject)
  end
end
