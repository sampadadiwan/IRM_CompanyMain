# Close report (KpiReportsController#mark_reviewed): approves every KPI still pending for the report's
# portfolio company — an upload stages values on one report per period it finds, so they sit on many
# reports, exactly the set Approve all acts on — then marks this report reviewed and moves every open
# journey of the portfolio company on.
#
# Idempotent: a second call approves nothing and leaves the report reviewed.
# Worked examples H5 — openspec/changes/kpi-report-journey/design.md#worked-examples
class KpiReportClose < Trailblazer::Operation
  step :approve_pending

  # The KPIs Close report approves: every pending KPI of the portfolio company in this fund — or, for a
  # company's own report (no portfolio company), only this report's, as mark_reviewed always did
  def self.pending_scope(kpi_report)
    return kpi_report.kpis.unapproved if kpi_report.portfolio_company_id.blank?

    Kpi.unapproved.where(entity_id: kpi_report.entity_id, portfolio_company_id: kpi_report.portfolio_company_id)
  end
  step :mark_reviewed
  step :progress_journeys

  # Every pending KPI of the portfolio company in this fund, approved through the usual service
  # (which also queues cumulation and percentage changes)
  def approve_pending(ctx, kpi_report:, user:, **)
    pending = KpiReportClose.pending_scope(kpi_report)
    ctx[:periods] = pending.distinct.count(:kpi_report_id)
    ids = pending.pluck(:id)
    KpiApproveService.call(ids, user.id) if ids.any?
    ctx[:approved] = ids.size
    true
  end

  def mark_reviewed(_ctx, kpi_report:, **)
    kpi_report.update!(status: 'reviewed')
  end

  # The approvals pass "Approve or reject KPIs" on every open report of the portfolio company (H10)
  def progress_journeys(_ctx, kpi_report:, user:, **)
    KpiReport.journey_progress_for_portco(kpi_report.entity_id, kpi_report.portfolio_company_id, actor: user)
    kpi_report.journey_progress!(actor: user) if kpi_report.portfolio_company_id.blank?
    true
  end
end
