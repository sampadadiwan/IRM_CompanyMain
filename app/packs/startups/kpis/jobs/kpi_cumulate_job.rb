class KpiCumulateJob < ApplicationJob
  queue_as :default

  # rubocop: disable Rails/SkipsModelValidations
  def perform(portfolio_company_id, user_id: nil)
    Chewy.strategy(:sidekiq) do
      kpi_reports = get_kpi_reports(portfolio_company_id)
      return unless kpi_reports.exists?

      # Cumulate KPIs for each report
      kpi_reports.each do |kpi_report|
        kpi_report.kpis.joins(:investor_kpi_mapping).cumulatable.each(&:cumulate)
        kpi_report.update_columns(cumulation_completed: true)
      rescue StandardError => e
        Rails.logger.error "Failed to cumulate KPI data for KpiReport #{kpi_report.id}: #{e.message}"
        send_notification("Failed to cumulate KPI data: #{e.message}", user_id, :error)
      end
    end
  end
  # rubocop: enable Rails/SkipsModelValidations

  def get_kpi_reports(portfolio_company_id)
    kpi_reports = KpiReport.where(portfolio_company_id: portfolio_company_id)
    from_date = 24.hours.ago

    # Process KPI reports that have not yet been cumulated or have been updated since from_date
    kpi_reports_just_updated = kpi_reports.joins(:kpis).where(updated_at: from_date..Time.current)
    kpi_reports_not_cumulated = kpi_reports.where(cumulation_completed: false)
    # Combine both conditions
    kpi_reports = kpi_reports_just_updated.or(kpi_reports_not_cumulated)
    # Ensure associated KPIs and mappings are loaded
    kpi_reports.includes(kpis: :investor_kpi_mapping).distinct
  end
end
