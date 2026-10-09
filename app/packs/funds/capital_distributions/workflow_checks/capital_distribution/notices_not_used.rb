# Skip for Generate notices / Approve notices: no email goes out, or the fund has no Distribution
# Template — most funds email investors without a notice (design Decision 7).
# Worked examples E1, E2, E3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class NoticesNotUsed < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.notices_not_used"
      self.label = "Skip: notices not used"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        reason = no_email_reason(dist)
        return pass(message: reason) if reason
        return pass(message: "No distribution notice template") unless notice_template?(dist)

        fail_with(message: "Notices apply")
      end
    end
  end
end
