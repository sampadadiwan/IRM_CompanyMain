# 5. Approve or reject KPIs — no KPI of the report's portfolio company awaits a decision. Counted for
# the whole portfolio company, not just this report: an upload stages values on one report per period
# it finds, so most pending KPIs sit on other reports (the same set Approve all acts on).
# The grid opens in a new tab with a banner back to this report (H19).
# Worked examples H4, H10, E13, H19 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class Approve < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.approve"
      self.label = "Approve or reject KPIs"
      self.workflowable_type = "KpiReport"
      self.how = "Approve or reject the staged KPIs on the portfolio company's KPI grid, or click Close report to approve them all."
      self.why = "Staged values are not used in charts and reports until they are approved."
      self.effects = "Approved values appear in charts and reports. Nothing is sent to the portfolio company."

      def call(report)
        # One indexed query (index_kpis_on_entity_pc_status_name): pending count and how many reports they sit on
        pending, periods = ::Kpi.unapproved.where(entity_id: report.entity_id, portfolio_company_id: report.portfolio_company_id)
                                .pick(Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT kpi_report_id)"))
        return pass(message: "No KPIs await a decision", passed_since: report.kpis.maximum(:approved_at)) if pending.to_i.zero?

        fail_with(message: "#{pending} #{'KPI'.pluralize(pending)} across #{periods} #{'period'.pluralize(periods)} #{pending == 1 ? 'awaits' : 'await'} a decision",
                  action_label: "Review pending KPIs", action_path: pending_grid_path(report), new_tab: true)
      end
    end
  end
end
