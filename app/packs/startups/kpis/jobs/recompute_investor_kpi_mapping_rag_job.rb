class RecomputeInvestorKpiMappingRagJob < ApplicationJob
  queue_as :default

  # Backs the "Recompute RAG Status" button on the mapping's show page — kicked off asynchronously,
  # same as KpiApproveService's KpiCumulateJob/KpiPercentageChangeJob triggers, rather than iterating
  # inline in the controller. A mapping's approved KPIs are normally one per reporting period (a
  # few dozen for a long-lived mapping), but running the loop in the request would still tie up a
  # web worker for it, and this keeps the pattern consistent with the rest of this controller family.
  def perform(investor_kpi_mapping_id, user_id)
    mapping = InvestorKpiMapping.find(investor_kpi_mapping_id)

    count = 0
    # includes: recompute_rag_status! reads each KPI's mapping (the same one for all) and report; preloaded per batch
    Kpi.approved.where(investor_kpi_mapping_id: mapping.id).includes(:investor_kpi_mapping, :kpi_report).find_each do |kpi|
      kpi.recompute_rag_status!
      count += 1
    end

    send_notification("Recomputed RAG status for #{count} KPI(s) under \"#{mapping.reported_kpi_name}\".", user_id, "success")
  end
end
