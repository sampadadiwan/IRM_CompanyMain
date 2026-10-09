# Skip for Email investors (and, through NoticesNotUsed / ReviewNotNeeded, the notice and review
# tasks): the distribution was imported, its Send Notification setting is off, or every commitment
# is set to Skip Doc Gen.
# Worked examples E2, E3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class NoEmail < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.no_email"
      self.label = "Skip: investors not emailed"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        reason = no_email_reason(dist)
        reason ? pass(message: reason) : fail_with(message: "Investors are emailed")
      end
    end
  end
end
