# Skip for Redeem units: the distribution has no unit prices, so no units are redeemed
# (Redeem Units is only offered with unit prices).
# Worked examples E7 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class NoUnitPrices < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.no_unit_prices"
      self.label = "Skip: no unit prices"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        dist.unit_prices.blank? ? pass(message: "The distribution has no unit prices") : fail_with(message: "Unit prices set")
      end
    end
  end
end
