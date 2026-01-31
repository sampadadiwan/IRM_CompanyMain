class KpiCumulateJob < ApplicationJob
  queue_as :default

  # rubocop: disable Rails/SkipsModelValidations, Metrics/MethodLength, Metrics/BlockLength
  def perform(portfolio_company_id, user_id: nil, force: false)
    Chewy.strategy(:sidekiq) do
      @error_msgs = []
      send_notification("Started KPI cumulation for PortfolioCompany ID: #{portfolio_company_id}", user_id, :info)

      kpi_reports = get_kpi_reports(portfolio_company_id, force: force)
      return unless kpi_reports.exists?

      Rails.logger.debug { "Found #{kpi_reports.count} KpiReports to process for PortfolioCompany ID: #{portfolio_company_id} (force: #{force})" }

      # 1. Aggregation Phase: Cumulate & Forward Fill
      # We iterate over the reports that need processing (mostly Monthly ones)
      kpi_reports.actuals.each do |kpi_report|
        Rails.logger.debug { "Cumulating KPIs for KpiReport ID: #{kpi_report.id}" }
        send_notification("Processing KPI cumulation for KpiReport ID: #{kpi_report.id} (As of: #{kpi_report.as_of})", user_id, :info)

        # Run Cumulate and Forward Fill
        # This might create new KPIs for Quarter/YTD reports or update existing ones
        kpi_report.kpis.joins(:investor_kpi_mapping)
                  .where(investor_kpi_mappings: { cumulate: %w[cumulate forward_fill] })
                  .find_each do |kpi|
                    kpi.cumulate(force: force)
                    @error_msgs.concat(kpi.cumulation_errors) if kpi.respond_to?(:cumulation_errors) && kpi.cumulation_errors.present?
                  end

        kpi_report.update_columns(cumulation_completed: true)
      rescue StandardError => e
        error_info = "Failed to cumulate KPI data for KpiReport #{kpi_report.id}: #{e.message}"
        Rails.logger.error error_info
        @error_msgs << { report: kpi_report.id, as_of: kpi_report.as_of, message: error_info }
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
          kpi.cumulate(force: force)
          @error_msgs.concat(kpi.cumulation_errors) if kpi.respond_to?(:cumulation_errors) && kpi.cumulation_errors.present?
        end
      rescue StandardError => e
        error_info = "Failed to compute KPI data for PortfolioCompany #{portfolio_company_id}: #{e.message}"
        Rails.logger.error error_info
        @error_msgs << { pc_id: portfolio_company_id, message: error_info }
      end

      if @error_msgs.present?
        msg = "Errors in KPI cumulation/computation for PortfolioCompany ID: #{portfolio_company_id}."
        send_notification("#{msg} Errors sent via email.", user_id, :error)

        user = User.find_by(id: user_id)
        if user
          # Clean and prepare for JSON-safe mailer transfer
          safe_report_data = @error_msgs.map do |err|
            err.transform_values(&:to_s).merge('status' => 'error')
          end

          EntityMailer.with(
            entity_id: user.entity_id,
            user_id: user.id,
            report_data: safe_report_data.to_json,
            subject: msg
          ).send_report.deliver_now
        end
      else
        send_notification("Successfully completed KPI cumulation for PortfolioCompany ID: #{portfolio_company_id}", user_id, :success)
      end
    end
  end
  # rubocop: enable Rails/SkipsModelValidations, Metrics/MethodLength, Metrics/BlockLength

  def get_kpi_reports(portfolio_company_id, force: false)
    kpi_reports = KpiReport.where(portfolio_company_id: portfolio_company_id)
    # In tests, we want to process all reports, but chronologically!
    # Also include those that don't have KPIs yet (for Compute)
    return kpi_reports.order(:as_of).distinct if Rails.env.test? || force

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
