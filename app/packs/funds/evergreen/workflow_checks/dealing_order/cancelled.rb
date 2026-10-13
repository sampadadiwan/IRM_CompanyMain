# Order journey check: Cancel units and send redemption advice.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class Cancelled < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.cancelled"
      self.label = "Cancel units and send redemption advice"
      self.workflowable_type = "DealingOrder"

      self.how = "Units are cancelled automatically when the redemption is marked paid."
      self.why = "Redeemed units must leave the register."
      self.effects = "The investor is emailed the redemption advice."

      def call(order)
        fill = fill_for(order)
        fill&.fund_unit_id && fill.document_sent_at ? pass(message: "Units cancelled") : fail_with(message: "Units not cancelled yet")
      end
    end
  end
end
