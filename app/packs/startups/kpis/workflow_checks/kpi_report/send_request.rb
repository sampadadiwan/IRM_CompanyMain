# 2. Send upload request — the portfolio company has been sent the upload link (or is already past
# that: it saved a draft or submitted). n/a when the fund uploads the KPIs itself (FundUploaded).
# Worked examples H14 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class SendRequest < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.send_request"
      self.label = "Send upload request"
      self.workflowable_type = "KpiReport"
      self.how = "Click Send upload request on the KPI report's page (or Send Reminder in the KPI grid's Actions menu)."
      self.why = "The portfolio company can't upload until it has the link."
      self.effects = "The portfolio company's KPI users are emailed an upload link."

      def call(report)
        return pass(message: "Upload link sent", passed_since: report.link_sent_at) if report.link_sent_at.present? || PAST_LINK_SENT.include?(report.status)

        fail_with(message: "Upload link not sent to #{portco_name(report)} yet",
                  action_label: "Send upload request", action_path: grid_path(report), action_target: SEND_REQUEST_BTN)
      end
    end
  end
end
