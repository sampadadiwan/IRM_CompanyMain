# 5. Check preview — an acknowledge task, like Review email; the person confirms they previewed
# the email (each payment's Preview Notification).
# Worked examples H4, E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class CheckPreview < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.check_preview"
      self.label = "Check preview (acknowledge)"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        pass(message: "Preview the distribution email", action_label: "View payments",
             action_path: distribution_path(dist), action_target: PAYMENTS_TAB)
      end
    end
  end
end
