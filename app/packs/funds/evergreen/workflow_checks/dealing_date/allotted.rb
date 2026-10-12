# Dealing-date journey check: Allot units.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class Allotted < WorkflowChecks::Base
      self.key = "dealing_date.allotted"
      self.label = "Allot units"
      self.workflowable_type = "DealingDate"
      self.how = "Units are allotted automatically when a confirmed subscription is paid."
      self.why = "Subscribers own units only once allotted."
      self.effects = "Without a contract-note template, investors are emailed straight away."

      def call(dealing_date)
        DealingProgress.new(dealing_date).units_allotted? ? pass(message: "Units allotted") : fail_with(message: "Units not allotted yet")
      end
    end
  end
end
