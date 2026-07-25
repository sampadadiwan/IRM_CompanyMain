class KpiCumulateJob < ApplicationJob
  queue_as :default

  # compute_percentage_change: true runs KpiPercentageChangeJob inline once cumulation finishes.
  # Callers (e.g. KpiApproveService) use this instead of queuing the percentage job themselves,
  # because two independently queued jobs have no ordering guarantee — the percentage job could
  # run before the Quarter/YTD/Year KPIs created here exist, leaving them without MoM/YoY changes.
  def perform(portfolio_company_id, user_id: nil, force: false, compute_percentage_change: false)
    Chewy.strategy(:sidekiq) do
      run_cumulation(portfolio_company_id, user_id, force)
    end

    # Runs last and UNCONDITIONALLY: run_cumulation may bail out early when no report needs
    # cumulating, but "nothing to cumulate" and "nothing to recompute percentages for" are
    # different questions — an approval with no cumulation work still needs its MoM/YoY changes
    # refreshed. Triggering the percentage job here (instead of the caller queuing it separately)
    # is what guarantees it runs over the cumulative KPIs written above. Guarded on user_id
    # because KpiPercentageChangeJob resolves companies via Pundit.policy_scope(User.find(user_id))
    # and would crash on a nil user.
    KpiPercentageChangeJob.perform_now(portfolio_company_id, user_id) if compute_percentage_change && user_id
  end

  private

  # The cumulation body, split out of #perform so its early return (no reports to process)
  # cannot short-circuit the percentage-change trigger above — that's exactly the bug this
  # structure prevents from reappearing.
  def run_cumulation(portfolio_company_id, user_id, force)
    @error_msgs = []
    send_notification("Started KPI cumulation for PortfolioCompany ID: #{portfolio_company_id}", user_id, :info)

    kpi_reports = get_kpi_reports(portfolio_company_id, force: force)
    return unless kpi_reports.exists?

    Rails.logger.debug { "Found #{kpi_reports.count} KpiReports to process for PortfolioCompany ID: #{portfolio_company_id} (force: #{force})" }

    # 1. Aggregation Phase: Cumulate & Forward Fill
    # We iterate over the reports that need processing (mostly Monthly ones)
    kpi_reports.each do |kpi_report|
      Rails.logger.debug { "Cumulating KPIs for KpiReport ID: #{kpi_report.id}" }
      send_notification("Processing KPI cumulation for KpiReport ID: #{kpi_report.id} (As of: #{kpi_report.as_of})", user_id, :info)

      # Run Cumulate and Forward Fill
      # This might create new KPIs for Quarter/YTD reports or update existing ones
      kpi_report.kpis.joins(:investor_kpi_mapping)
                .where(investor_kpi_mappings: { autofill: %w[cumulate forward_fill] })
                .find_each do |kpi|
                  kpi.autofill(force: force)
                  @error_msgs.concat(kpi.autofill_errors) if kpi.respond_to?(:autofill_errors) && kpi.autofill_errors.present?
                end

      kpi_report.update_columns(autofill_completed: true)
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
      InvestorKpiMapping.where(investor_id: portfolio_company_id, autofill: 'compute').find_each do |mapping|
        # We need an instance to call the concern method.
        # Create a temporary KPI object to trigger the logic defined in the Concern.
        kpi = Kpi.new(
          portfolio_company_id: portfolio_company_id,
          entity_id: mapping.entity_id,
          name: mapping.standard_kpi_name,
          investor_kpi_mapping: mapping
        )
        kpi.autofill(force: force)
        @error_msgs.concat(kpi.autofill_errors) if kpi.respond_to?(:autofill_errors) && kpi.autofill_errors.present?
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

  def get_kpi_reports(portfolio_company_id, force: false)
    kpi_reports = KpiReport.where(portfolio_company_id: portfolio_company_id)
    # In tests, we want to process all reports, but chronologically!
    # Also include those that don't have KPIs yet (for Compute)
    return kpi_reports.order(:as_of).distinct if Rails.env.test? || force

    from_date = 24.hours.ago

    # Process KPI reports that have not yet been cumulated or whose KPIS changed since from_date.
    # The recency check must look at kpis.updated_at, not kpi_reports.updated_at: approving or
    # editing a KPI touches the Kpi row only, so filtering on the report's own timestamp missed
    # approvals on older reports and left their Quarter/YTD/Year totals stale.
    kpi_reports_just_updated = kpi_reports.joins(:kpis).where(kpis: { updated_at: from_date..Time.current })
    kpi_reports_not_cumulated = kpi_reports.where(autofill_completed: false)
    # Combine both conditions
    kpi_reports = kpi_reports_just_updated.or(kpi_reports_not_cumulated)
    # Ensure associated KPIs and mappings are loaded
    kpi_reports.includes(kpis: :investor_kpi_mapping).distinct
  end
end
