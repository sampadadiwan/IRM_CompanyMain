# 8. Email investors — every emailable payment has been emailed. notification_sent is written with
# update_column (no timestamp), so the pass time falls back to when it was noticed.
# Worked examples H7 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class EmailInvestors < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.email_investors"
      self.label = "Email investors"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        emailable = emailable_payments(dist)
        total = emailable.count
        sent = emailable.where(notification_sent: true).count
        return pass(message: "#{total} #{'investor'.pluralize(total)} emailed") if total.positive? && sent == total

        fail_with(message: "#{sent} of #{total} investors emailed", action_label: "Send Payment Notifications",
                  action_path: distribution_path(dist), action_target: NOTIFY_BTN)
      end
    end
  end
end
