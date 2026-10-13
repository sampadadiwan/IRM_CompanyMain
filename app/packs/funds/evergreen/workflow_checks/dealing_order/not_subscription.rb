# Order journey check: Skip: not a subscription.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class NotSubscription < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.not_subscription"
      self.label = "Skip: not a subscription"
      self.workflowable_type = "DealingOrder"

      def call(order)
        order.subscription? ? fail_with(message: "Subscription") : pass(message: "Not a subscription")
      end
    end
  end
end
