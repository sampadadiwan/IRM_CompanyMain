class KpiApproveService
  def self.call(kpi_ids, user_id)
    @result_kpis = kpi_ids.map { |kpi_id| KpiApprover.call(kpi_id, user_id) }

    # After approval, trigger post-processing jobs
    KpiPercentageChangeJob.perform_later(@result_kpis.pluck(:portfolio_company_id).uniq, user_id)
    KpiCumulateJob.perform_later(@result_kpis.pluck(:portfolio_company_id).uniq)

    @result_kpis
  end
end
