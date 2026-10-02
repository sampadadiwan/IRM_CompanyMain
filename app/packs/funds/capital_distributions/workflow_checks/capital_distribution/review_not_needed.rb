# Skip for Review email / Check preview: no email goes out, or investors have already been emailed
# (a review after sending can't change anything).
# Worked examples E2, E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class ReviewNotNeeded < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.review_not_needed"
      self.label = "Skip: no email, or already emailed"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        reason = no_email_reason(dist)
        return pass(message: reason) if reason
        return pass(message: "Investors have already been emailed") if all_emailed?(dist)

        fail_with(message: "Review needed")
      end
    end
  end
end
