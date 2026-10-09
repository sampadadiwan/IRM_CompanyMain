# Skip: the call was imported, or is set not to notify investors — no notices or email tasks.
# Worked examples E3, E23 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class NoticesNotApplicable < WorkflowChecks::Base
      include Support

      self.key = "capital_call.notices_not_applicable"
      self.label = "Skip: notices not applicable"
      self.workflowable_type = "CapitalCall"

      def call(call)
        return pass(message: "Notices are not sent for imported calls") if call.manual_generation
        return pass(message: "This call is set to not notify investors") unless call.send_call_notice_flag

        fail_with(message: "Notices apply")
      end
    end
  end
end
