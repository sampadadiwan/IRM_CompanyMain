# Order journey check: Skip: not a redemption.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class NotRedemption < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.not_redemption"
      self.label = "Skip: not a redemption"
      self.workflowable_type = "DealingOrder"

      def call(order)
        order.redemption? ? fail_with(message: "Redemption") : pass(message: "Not a redemption")
      end
    end
  end
end
