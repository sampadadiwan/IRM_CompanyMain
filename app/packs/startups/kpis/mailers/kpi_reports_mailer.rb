class KpiReportsMailer < ApplicationMailer
  def send_reminder
    @kpi_report = KpiReport.find params[:kpi_report_id]
    @portfolio_company = @kpi_report.portfolio_company

    send_mail(subject: "Reminder: KPI Reporting for #{@kpi_report.for_name} - #{@kpi_report.as_of}")
  end
end
