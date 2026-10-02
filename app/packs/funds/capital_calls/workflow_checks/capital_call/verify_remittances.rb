# 10. Verify remittances — every remittance is verified.
# Worked examples H7, E18 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class VerifyRemittances < WorkflowChecks::Base
      include Support

      self.key = "capital_call.verify_remittances"
      self.label = "Verify remittances"
      self.workflowable_type = "CapitalCall"

      def call(call)
        total = remittances(call).count
        pending = remittances(call).where(verified: false).count
        # updated_at only moves later than the verification, so this is never earlier than the truth
        return pass(message: "#{total} remittances verified", passed_since: remittances(call).maximum(:updated_at)) if total.positive? && pending.zero?

        fail_with(message: "#{pending} of #{total} remittances not verified", action_label: "View remittances",
                  action_path: call_path(call), action_target: REMITTANCES_TAB)
      end
    end
  end
end
