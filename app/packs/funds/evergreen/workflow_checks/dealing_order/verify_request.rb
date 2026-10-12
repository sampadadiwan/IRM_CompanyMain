# Order journey check: Verify request.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class VerifyRequest < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.verify_request"
      self.label = "Verify request"
      self.workflowable_type = "DealingOrder"

      self.how = "Check the request comes from an authorised signatory and click Verify signatory."
      self.why = "Redemptions move money out of the fund."
      self.effects = "The order moves on to acceptance. The investor isn't emailed."

      def call(order)
        order.signatory_verified_at ? pass(message: "Signatory verified", passed_since: order.signatory_verified_at) : fail_with(message: "Verify the signatory", action_label: "Open order", action_path: order_path(order))
      end
    end
  end
end
