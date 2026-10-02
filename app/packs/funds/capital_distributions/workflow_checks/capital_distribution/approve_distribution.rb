# 6. Approve distribution — the distribution is approved. There is no approved_at column, so the
# pass time comes from the audit that set approved (as for capital calls).
# Worked examples H5 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class ApproveDistribution < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.approve_distribution"
      self.label = "Approve distribution"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        unless dist.approved
          return fail_with(message: "The distribution is not approved yet", action_label: "Approve",
                           action_path: distribution_path(dist), action_target: APPROVE_BTN)
        end

        pass(message: "Distribution approved", passed_since: approved_at(dist))
      end

      private

      # The latest audit that switched approved on (audits are indexed by auditable)
      def approved_at(dist)
        dist.audits.where(action: "update").order(created_at: :desc).limit(20)
            .find { |a| Array(a.audited_changes["approved"]).last == true }&.created_at
      end
    end
  end
end
