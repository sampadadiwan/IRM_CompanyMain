# 3. Approve notices — no generated notice on the distribution's payments is unapproved. Only
# approved notices are attached to the investor email (CapitalDistributionPaymentsMailer).
# Worked examples H3, E12 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class ApproveNotices < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.approve_notices"
      self.label = "Approve notices"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        notices = generated_notices(dist)
        total = notices.count
        waiting = notices.where(approved: false).count
        # updated_at only moves later than the approval, so this is never earlier than the truth
        return pass(message: "#{total} #{'notice'.pluralize(total)} approved", passed_since: notices.maximum(:updated_at)) if total.positive? && waiting.zero?

        return fail_with(message: "No notices generated yet") if total.zero?

        # The panel clicks the Actions menu's "View Generated Notices To Approve" link (a new window);
        # pending_notices_path is the fallback when that link isn't rendered for the viewer
        fail_with(message: "#{waiting} of #{total} notices await approval", action_label: "View notices to approve",
                  action_path: pending_notices_path(dist), action_target: VIEW_NOTICES_TO_APPROVE_BTN)
      end
    end
  end
end
