# 1. Set up KPI mappings — the portfolio company has at least one KPI mapping an import can fill
# (computed mappings are derived, so they don't count — same rule as KpiReport#no_kpi_mappings?).
# Worked examples H15, E16 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class SetupMappings < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.setup_mappings"
      self.label = "Set up KPI mappings"
      self.workflowable_type = "KpiReport"
      self.how = "Add the portfolio company's KPI mappings on its KPI Mappings tab, or import them."
      self.why = "An import only reads the KPIs that are mapped; without mappings it finds nothing."
      self.effects = "Nothing is sent to anyone."

      def call(report)
        count = InvestorKpiMapping.not_compute.where(investor_id: report.portfolio_company_id).count
        return pass(message: "#{count} KPI #{'mapping'.pluralize(count)}") if count.positive?

        fail_with(message: "No KPI mappings — imports will find nothing",
                  action_label: "Open KPI mappings", action_path: mappings_path(report))
      end
    end
  end
end
