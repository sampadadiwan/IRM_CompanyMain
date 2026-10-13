# Order journey check: Skip: no money before dealing.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class MoneyNotNeeded < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.money_not_needed"
      self.label = "Skip: no money before dealing"
      self.workflowable_type = "DealingOrder"

      def call(order)
        order.subscription? && order.setting.pre_funded? ? fail_with(message: "Paid before dealing") : pass(message: "Not paid before dealing")
      end
    end
  end
end
