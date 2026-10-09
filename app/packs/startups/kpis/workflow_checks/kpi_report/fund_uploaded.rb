# Skip check for "Send upload request" and "Submit KPIs": the report isn't set up for the portfolio
# company to upload, so the fund uploads the KPIs itself.
# Worked examples H14 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class FundUploaded < WorkflowChecks::Base
      self.key = "kpi_report.fund_uploaded"
      self.label = "Uploaded by the fund"
      self.workflowable_type = "KpiReport"

      def call(report)
        return pass(message: "Uploaded by the fund") unless report.enable_portco_upload?

        fail_with(message: "The portfolio company uploads")
      end
    end
  end
end
