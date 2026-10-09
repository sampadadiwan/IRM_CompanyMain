# 6. Check preview — an acknowledge task, like Review custom notification; the person confirms they
# previewed the email an investor will receive, with its call notice attached. The preview lives on
# each remittance (its Actions menu → Preview Notification), so the message says where to find it and
# the second button opens the Remittances tab.
#
# Result.review (not pass) is what makes the panel show this message and that button beside
# "Mark reviewed".
# Worked examples H4 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class CheckPreview < WorkflowChecks::Base
      include Support

      self.key = "capital_call.check_preview"
      self.label = "Check preview (acknowledge)"
      self.workflowable_type = "CapitalCall"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Open one remittance's Preview Notification, then click Mark reviewed."
      self.why = "The preview shows the email with placeholders filled in and the notice attached, which catches a broken merge field."
      self.effects = "Records who previewed it. No emails are sent."

      def call(call)
        WorkflowChecks::Result.review(
          message: "On the Remittances tab, open a remittance's Actions menu and choose Preview Notification " \
                   "to see the email an investor will receive, with their notice attached — then mark reviewed",
          action_label: "Open remittances", action_path: call_path(call), action_target: REMITTANCES_TAB
        )
      end
    end
  end
end
