class KpiCumulateJob < ApplicationJob
  queue_as :default

  # rubocop: disable Rails/SkipsModelValidations
  def perform(portfolio_company_id, user_id: nil)
    Chewy.strategy(:sidekiq) do
      kpi_reports = get_kpi_reports(portfolio_company_id)
      return unless kpi_reports.exists?

      Rails.logger.debug { "Found #{kpi_reports.count} KpiReports to process for PortfolioCompany ID: #{portfolio_company_id}" }

      # 1. Aggregation Phase: Cumulate & Forward Fill
      # We iterate over the reports that need processing (mostly Monthly ones)
      kpi_reports.actuals.each do |kpi_report|
        Rails.logger.debug { "Cumulating KPIs for KpiReport ID: #{kpi_report.id}" }

        # Run Cumulate and Forward Fill
        # This might create new KPIs for Quarter/YTD reports or update existing ones
        kpi_report.kpis.joins(:investor_kpi_mapping)
                  .where(investor_kpi_mappings: { cumulate: %w[cumulate forward_fill] })
                  .find_each(&:cumulate)

        kpi_report.update_columns(cumulation_completed: true)
      rescue StandardError => e
        Rails.logger.error "Failed to cumulate KPI data for KpiReport #{kpi_report.id}: #{e.message}"
        send_notification("Failed to cumulate KPI data: #{e.message}", user_id, :error)
      end

      # 2. Computation Phase: Compute
      # This runs AFTER aggregation is complete for all processed reports.
      # It finds all mappings that require computation and triggers the calculation.
      # The computation logic in KpiCumulative#perform_computation iterates over all relevant Q/YTD reports for the PC.
      begin
        InvestorKpiMapping.where(investor_id: portfolio_company_id, cumulate: 'compute').find_each do |mapping|
          # We need an instance to call the concern method.
          # Create a temporary KPI object to trigger the logic defined in the Concern.
          kpi = Kpi.new(
            portfolio_company_id: portfolio_company_id,
            entity_id: mapping.entity_id,
            name: mapping.standard_kpi_name,
            investor_kpi_mapping: mapping
          )
          kpi.cumulate
        end
      rescue StandardError => e
        Rails.logger.error "Failed to compute KPI data for PortfolioCompany #{portfolio_company_id}: #{e.message}"
        send_notification("Failed to compute KPI data: #{e.message}", user_id, :error)
      end
    end
  end
  # rubocop: enable Rails/SkipsModelValidations

  def get_kpi_reports(portfolio_company_id)
    kpi_reports = KpiReport.where(portfolio_company_id: portfolio_company_id)
    # In tests, we want to process all reports, but chronologically!
    # Also include those that don't have KPIs yet (for Compute)
    return kpi_reports.order(:as_of).distinct if Rails.env.test?

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
