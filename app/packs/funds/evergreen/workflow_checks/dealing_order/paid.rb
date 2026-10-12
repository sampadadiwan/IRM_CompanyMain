# Order journey check: Pay redemption.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class Paid < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.paid"
      self.label = "Pay redemption"
      self.workflowable_type = "DealingOrder"

      self.how = "Mark the redemption paid on the dealing date's settlement tracker."
      self.why = "The fund pays the investor for redeemed units."
      self.effects = "Units are cancelled and the redemption advice is emailed."

      def call(order)
        fill = fill_for(order)
        fill&.capital_distribution_payment&.completed ? pass(message: "Paid") : fail_with(message: "Redemption not paid yet")
      end
    end
  end
end
