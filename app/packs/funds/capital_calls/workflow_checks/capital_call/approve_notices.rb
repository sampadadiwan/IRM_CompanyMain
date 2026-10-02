# 4. Approve notices — no generated notice on the call is unapproved.
# Worked examples H3, E7 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class ApproveNotices < WorkflowChecks::Base
      include Support

      self.key = "capital_call.approve_notices"
      self.label = "Approve notices"
      self.workflowable_type = "CapitalCall"

      def call(call)
        notices = generated_notices(call)
        total = notices.count
        waiting = notices.where(approved: false).count
        if total.positive? && waiting.zero?
          # updated_at only moves later than the approval, so this is never earlier than the truth
          return pass(message: "#{total} notices approved", passed_since: notices.maximum(:updated_at))
        end

        # The panel clicks the Actions menu's "View Generated Notices To Approve" link (a new window);
        # pending_notices_path is the fallback when that link isn't rendered for the viewer
        fail_with(message: "#{waiting} of #{total} call notices await approval", action_label: "View notices to approve",
                  action_path: pending_notices_path(call), action_target: VIEW_NOTICES_TO_APPROVE_BTN)
      end
    end
  end
end
