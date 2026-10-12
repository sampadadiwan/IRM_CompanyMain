# Order journey check: Ready to deal.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class ReadyToDeal < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.ready_to_deal"
      self.label = "Ready to deal"
      self.workflowable_type = "DealingOrder"

      self.how = "Complete the steps above."
      self.why = "Only ready orders are priced on a dealing date."
      self.effects = "The order is priced on its dealing date."

      def call(order)
        OrderJourneyStatus.ready_to_deal?(order) ? pass(message: "Ready to deal") : fail_with(message: "Waiting on: #{OrderJourneyStatus.waiting_on(order)}")
      end
    end
  end
end
