class KpiCumulateJob < ApplicationJob
  queue_as :default

  def perform(kpi_report: nil, user_id: nil, portfolio_company_id: nil, from_date: nil)
    Chewy.strategy(:sidekiq) do
      kpi_reports = if kpi_report
                      KpiReport.where(id: kpi_report.id)
                    else
                      from_date ||= 24.hours.ago
                      # Process KPI reports that have been updated in the last 24 hours
                      KpiReport.where(updated_at: from_date..).joins(kpis: :investor_kpi_mapping)
                    end

      kpi_reports = kpi_reports.where(portfolio_company_id: portfolio_company_id) if portfolio_company_id.present?

      return unless kpi_reports.exists?

      # Cumulate KPIs for each report
      kpi_reports.each do |kpi_report|
        kpi_report.kpis.joins(:investor_kpi_mapping).cumulatable.each do |kpi|
          kpi.cumulate
        end
      rescue StandardError => e
        Rails.logger.error "Failed to cumulate KPI data for KpiReport #{kpi_report.id}: #{e.message}"
        send_notification("Failed to cumulate KPI data: #{e.message}", user_id, :error)
      end
    end
  end
end
