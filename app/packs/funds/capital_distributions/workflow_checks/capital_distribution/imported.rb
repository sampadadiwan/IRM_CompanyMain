# Skip for Approve distribution: an imported distribution is history, not approved in CapHive.
# Only matters if an admin points imported distributions at the Full journey.
# Worked examples H9 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class Imported < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.imported"
      self.label = "Skip: imported distribution"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        dist.manual_generation ? pass(message: "Imported distributions are not approved in CapHive") : fail_with(message: "Not imported")
      end
    end
  end
end
