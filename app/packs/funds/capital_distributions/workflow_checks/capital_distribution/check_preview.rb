# 5. Check preview — an acknowledge task, like Review custom notification; the person confirms they
# previewed the email an investor will receive. The preview lives on each payment's own page (its
# Actions menu → Preview Notification), so the message says where to find it and the second button
# opens the Payments tab.
#
# Result.review (not pass) is what makes the panel show this message and that button beside
# "Mark reviewed".
# Worked examples H4, E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class CheckPreview < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.check_preview"
      self.label = "Check preview (acknowledge)"
      self.workflowable_type = "CapitalDistribution"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Open one payment's Preview Notification, then click Mark reviewed."
      self.why = "The preview shows the email with placeholders filled in, which catches a broken merge field before investors see it."
      self.effects = "Records who previewed it. No emails are sent."

      def call(dist)
        WorkflowChecks::Result.review(
          message: "On the Payments tab, open a payment and choose Preview Notification from its Actions menu " \
                   "to see the email an investor will receive — then mark reviewed",
          action_label: "Open payments", action_path: distribution_path(dist), action_target: PAYMENTS_TAB
        )
      end
    end
  end
end
