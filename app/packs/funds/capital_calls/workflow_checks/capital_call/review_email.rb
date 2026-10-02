# 5. Review email — an acknowledge task: what makes it done is the person's "Mark reviewed"; this
# check just offers the link to the call's notification settings.
# Worked examples H4, E12 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class ReviewEmail < WorkflowChecks::Base
      include Support

      self.key = "capital_call.review_email"
      self.label = "Review email (acknowledge)"
      self.workflowable_type = "CapitalCall"

      def call(call)
        pass(message: "Review the call email", action_label: "Open the call", action_path: call_path(call))
      end
    end
  end
end
