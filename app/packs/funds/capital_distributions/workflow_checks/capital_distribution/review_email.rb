# 4. Review email — an acknowledge task: what makes it done is the person's "Mark reviewed"; this
# check just offers the distribution's Notification tab, where the email is set up.
# Worked examples H4, E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class ReviewEmail < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.review_email"
      self.label = "Review email (acknowledge)"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        pass(message: "Review the distribution email", action_label: "Open the notification",
             action_path: distribution_path(dist), action_target: NOTIFICATION_TAB)
      end
    end
  end
end
