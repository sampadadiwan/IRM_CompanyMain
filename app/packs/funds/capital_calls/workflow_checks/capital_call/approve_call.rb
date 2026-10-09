# 7. Approve call — the call is approved. Passed time comes from the audit that set approved.
# Worked examples H5, E10b — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class ApproveCall < WorkflowChecks::Base
      include Support

      self.key = "capital_call.approve_call"
      self.label = "Approve call"
      self.workflowable_type = "CapitalCall"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Click Approve (needs the Approver role)."
      self.why = "Approval locks the call's figures; notices can only be sent after it."
      self.effects = "The call is approved and Send Notification is unlocked. No emails are sent; notices go out only on Send."

      def call(call)
        unless call.approved
          return fail_with(message: "The call is not approved yet", action_label: "Approve",
                           action_path: call_path(call), action_target: APPROVE_BTN)
        end

        pass(message: "Call approved", passed_since: approved_at(call))
      end

      private

      # The latest audit that switched approved on (audits are indexed by auditable)
      def approved_at(call)
        call.audits.where(action: "update").order(created_at: :desc).limit(20)
            .find { |a| Array(a.audited_changes["approved"]).last == true }&.created_at
      end
    end
  end
end
