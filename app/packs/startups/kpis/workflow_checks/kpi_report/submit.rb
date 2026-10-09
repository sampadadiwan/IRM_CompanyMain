# 3. Submit KPIs — the portfolio company submitted the report (it may since have been closed). After a
# failed import the report is reopened for the portco, and this step says so.
# Worked examples E12, X4 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class Submit < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.submit"
      self.label = "Submit KPIs"
      self.workflowable_type = "KpiReport"
      self.how = "The portfolio company uploads its workbook and clicks Submit Report."
      self.why = "Nothing can be imported until the portfolio company submits."
      self.effects = "The fund's KPI team is told once the import has staged the data."

      def call(report)
        return pass(message: "Submitted", passed_since: report.submitted_at) if SUBMITTED.include?(report.status)
        return fail_with(message: "Import failed — reopened for the portco") if report.import_status == "failed"

        fail_with(message: "Waiting for #{portco_name(report)} to submit")
      end
    end
  end
end
