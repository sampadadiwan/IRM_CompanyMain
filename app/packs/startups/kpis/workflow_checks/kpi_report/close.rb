# 6. Close report — someone clicked Close report (KpiReportsController#mark_reviewed), which approves
# what is still pending for the portfolio company and marks the report reviewed.
# Worked examples H5 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class Close < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.close"
      self.label = "Close report"
      self.workflowable_type = "KpiReport"
      self.how = "Click Close report on the KPI report."
      self.why = "Closing says this period's KPIs are final."
      self.effects = "Any KPIs still pending for the portfolio company are approved. Nothing is sent to the portfolio company."

      def call(report)
        return pass(message: "Closed") if report.status_reviewed?

        fail_with(message: "Not closed yet", action_label: "Close report",
                  action_path: report_path(report), action_target: CLOSE_BTN)
      end
    end
  end
end
