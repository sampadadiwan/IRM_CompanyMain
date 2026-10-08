# Skip for Allocate units: the call has no unit prices, so no units are allocated.
# Worked examples E4 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class NoUnitPrices < WorkflowChecks::Base
      include Support

      self.key = "capital_call.no_unit_prices"
      self.label = "Skip: no unit prices"
      self.workflowable_type = "CapitalCall"

      def call(call)
        call.unit_prices.blank? ? pass(message: "No unit prices set on this call") : fail_with(message: "Unit prices set")
      end
    end
  end
end
