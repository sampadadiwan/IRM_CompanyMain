# Order journey check: Collect subscription money.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class CollectMoney < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.collect_money"
      self.label = "Collect subscription money"
      self.workflowable_type = "DealingOrder"

      self.how = "Record and verify the subscriber's payment on the dealing date's settlement tracker."
      self.why = "Funds paid before dealing deal only cleared money."
      self.effects = "The order becomes ready to deal. The investor isn't emailed."

      def call(order)
        order.fully_paid? ? pass(message: "Money received") : fail_with(message: "Awaiting money")
      end
    end
  end
end
