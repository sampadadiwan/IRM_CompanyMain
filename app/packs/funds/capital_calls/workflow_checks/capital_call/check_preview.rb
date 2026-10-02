# 6. Check preview — an acknowledge task, like Review email; the person confirms they previewed it.
# Worked examples H4 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class CheckPreview < WorkflowChecks::Base
      include Support

      self.key = "capital_call.check_preview"
      self.label = "Check preview (acknowledge)"
      self.workflowable_type = "CapitalCall"

      def call(call)
        pass(message: "Preview the call email", action_label: "Open the call", action_path: call_path(call))
      end
    end
  end
end
