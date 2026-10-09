# 7 (optional, added by an admin). Send completion email — someone clicked Send completion email, which
# emailed the portfolio company's manager (else the step's actors, else the Kpi team).
# Worked examples H8, E10, E11 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class SendCompletionEmail < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.send_completion_email"
      self.label = "Send completion email"
      self.workflowable_type = "KpiReport"
      self.how = "Click Send completion email on the KPI report. Pick the recipients as this step's actors."
      self.why = "Tells the people who need to know that this portfolio company's period is done."
      self.effects = "The portfolio company's manager (else this step's actors, else the Kpi team) is emailed. The portfolio company is not."

      def call(report)
        return pass(message: "Completion email sent", passed_since: report.completion_notified_at) if report.completion_notified_at.present?

        fail_with(message: "Completion email not sent", action_label: "Send completion email",
                  action_path: report_path(report), action_target: SEND_COMPLETION_BTN)
      end
    end
  end
end
