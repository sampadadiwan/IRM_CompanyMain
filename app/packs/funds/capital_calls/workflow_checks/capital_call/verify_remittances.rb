# 10. Verify remittances — every remittance is verified.
# Worked examples H7, E18 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class VerifyRemittances < WorkflowChecks::Base
      include Support

      self.key = "capital_call.verify_remittances"
      self.label = "Verify remittances"
      self.workflowable_type = "CapitalCall"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Click Verify Pending Remittances once payments are matched."
      self.why = "Only verified remittances get fund units, so this confirms each payment really arrived."
      self.effects = "Verified remittances count as collected. If the call sends payment notifications, each investor is emailed a payment receipt."

      def call(call)
        total = remittances(call).count
        pending = remittances(call).where(verified: false).count
        # updated_at only moves later than the verification, so this is never earlier than the truth
        return pass(message: "#{total} remittances verified", passed_since: remittances(call).maximum(:updated_at)) if total.positive? && pending.zero?

        # Clicks the Remittances tab's "Verify Pending Remittances" (its confirm modal runs as usual);
        # that button exists only once the call is approved — before then the link just opens the call
        fail_with(message: "#{pending} of #{total} remittances not verified", action_label: "Verify Pending Remittances",
                  action_path: call_path(call), action_target: BULK_VERIFY_BTN)
      end
    end
  end
end
