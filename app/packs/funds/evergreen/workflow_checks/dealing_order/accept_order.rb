# Order journey check: Accept order.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class AcceptOrder < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.accept_order"
      self.label = "Accept order"
      self.workflowable_type = "DealingOrder"

      self.how = "A GP approver opens the order and clicks Accept (or Reject with a reason)."
      self.why = "The GP decides which orders the fund takes."
      self.effects = "Accepting moves the order on; rejecting cancels it and emails the investor."

      def call(order)
        order.accepted_at ? pass(message: "Accepted", passed_since: order.accepted_at) : fail_with(message: "Waiting for GP acceptance", action_label: "Open order", action_path: order_path(order))
      end
    end
  end
end
