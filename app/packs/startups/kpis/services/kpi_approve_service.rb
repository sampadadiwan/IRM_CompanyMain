# frozen_string_literal: true

# Orchestrates KPI approval and triggers post-processing (autofill recomputation
# and percentage-change recalculation). Passes the approved KPIs' source report
# IDs to the cumulation job so it only reprocesses what changed — the cumulation
# concern itself handles writing to downstream Quarter/YTD/Year reports.
class KpiApproveService
  # @param kpi_ids [Array<Integer>] IDs of KPIs to approve
  # @param user_id [Integer] ID of the user performing the approval
  # @return [Array<Kpi>] the approved KPI records
  def self.call(kpi_ids, user_id)
    @result_kpis = kpi_ids.map { |kpi_id| KpiApprover.call(kpi_id, user_id) }

    # After approval, trigger post-processing.
    # Percentage changes must be computed AFTER cumulation, because cumulation creates/updates the
    # Quarter/YTD/Year KPIs and those need percentage changes too. Previously both jobs were queued
    # independently, so the percentage job could run first and leave the freshly cumulated KPIs
    # with stale or missing MoM/YoY changes. compute_percentage_change: true makes KpiCumulateJob
    # run the percentage job itself (perform_now) at the end, guaranteeing the ordering.
    #
    # report_ids scopes the job to only the reports containing the approved KPIs.
    # The KpiCumulative concern handles writing to downstream Quarter/YTD/Year
    # reports internally — we only need to feed it the source reports.
    portco_ids = @result_kpis.pluck(:portfolio_company_id).uniq
    source_report_ids = @result_kpis.map(&:kpi_report_id).uniq

    KpiCumulateJob.perform_later(
      portco_ids,
      user_id: user_id,
      force: true,
      report_ids: source_report_ids,
      compute_percentage_change: true
    )

    @result_kpis
  end
end
