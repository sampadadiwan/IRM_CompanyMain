# Dealing-date journey check: Cancel units.
# Worked examples H24, E32 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class UnitsCancelled < WorkflowChecks::Base
      self.key = "dealing_date.units_cancelled"
      self.label = "Cancel units"
      self.workflowable_type = "DealingDate"
      self.how = "Units are cancelled automatically when a redemption is marked paid."
      self.why = "Redeemed units must leave the register."
      self.effects = "Without a redemption-advice template, investors are emailed straight away."

      def call(dealing_date)
        DealingProgress.new(dealing_date).units_cancelled? ? pass(message: "Units cancelled") : fail_with(message: "Units not cancelled yet")
      end
    end
  end
end
