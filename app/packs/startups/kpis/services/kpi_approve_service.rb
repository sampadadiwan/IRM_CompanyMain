class KpiApproveService
  def self.call(kpi_ids, user_id)
    @result_kpis = kpi_ids.map { |kpi_id| KpiApprover.call(kpi_id, user_id) }

    # After approval, trigger post-processing.
    # Percentage changes must be computed AFTER cumulation, because cumulation creates/updates the
    # Quarter/YTD/Year KPIs and those need percentage changes too. Previously both jobs were queued
    # independently, so the percentage job could run first and leave the freshly cumulated KPIs
    # with stale or missing MoM/YoY changes. compute_percentage_change: true makes KpiCumulateJob
    # run the percentage job itself (perform_now) at the end, guaranteeing the ordering.
    KpiCumulateJob.perform_later(@result_kpis.pluck(:portfolio_company_id).uniq, user_id: user_id, compute_percentage_change: true)

    @result_kpis
  end
end
