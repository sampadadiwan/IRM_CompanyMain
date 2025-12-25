class KpiReportsMailer < ApplicationMailer
  # Send a reminder email to a portfolio company user to report their KPIs.
  def send_reminder
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company

    subject = "Reminder to report KPIs for #{@kpi_report.for_name} - #{@kpi_report.as_of}"
    send_mail(subject:)
  end
end
