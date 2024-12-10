class FundLlmReportJob < ApplicationJob
  queue_as :low

  def perform(fund_id, user_id, report_type, report_template_name: "Report Template", start_date: nil, end_date: nil)
    Chewy.strategy(:sidekiq) do
      fund = Fund.find(fund_id)
      case report_type
      when "KpiReport"
        kpi_reports(fund, user_id, report_template_name, start_date:, end_date:)
      when "AggregatePortfolioInvestment"
        api_reports(fund, user_id, report_template_name, start_date:, end_date:)
      else
        Rails.logger.debug { "Unknown report type: #{report_type}" }
        raise "Unknown report type: #{report_type}"
      end
    rescue StandardError => e
      Rails.logger.debug { "Failed to generate report: #{e.message}" }
      send_notification("Failed to generate report: #{e.message}", user_id)
    end
  end

  def kpi_reports(fund, user_id, report_template_name, start_date: nil, end_date: nil)
    apis = fund.aggregate_portfolio_investments
    apis.each do |api|
      send_notification("Generating report for portfolio company: #{api.portfolio_company.investor_name}", user_id)

      # Get the kpi for this api which are within the date range
      kpi_reports = api.entity.kpi_reports.where(portfolio_company_id: api.portfolio_company_id).where(as_of: start_date..end_date).order(as_of: :desc)

      kpi_reports.each do |kpi_report|
        FolderLlmReportJob.perform_now(kpi_report.document_folder_id, user_id, "KpiReport", report_template_name:)
      end

      next if kpi_reports.present?

      msg = "Generate Report: No KPI reports found for portfolio company: #{api.portfolio_company.investor_name}"
      Rails.logger.debug { msg }
      send_notification(msg, user_id)
    end
  end

  def api_reports(fund, user_id, report_template_name, start_date: nil, end_date: nil)
    apis = fund.aggregate_portfolio_investments
    apis.each do |api|
      # Get the latest folder created for this api
      latest_api_folder = api.document_folder.children.order(created_at: :desc).first
      if latest_api_folder.present?
        FolderLlmReportJob.perform_now(latest_api_folder.id, user_id, "AggregatePortfolioInvestment", report_template_name:)
      else
        msg = "Generate Report: No folder found for AggregatePortfolioInvestment: #{api.portfolio_company.investor_name}"
        Rails.logger.debug { msg }
        send_notification(msg, user_id)
      end
    end
  end
end
