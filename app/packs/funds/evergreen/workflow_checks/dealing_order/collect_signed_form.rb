# Order journey check: Collect signed subscription form.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class CollectSignedForm < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.collect_signed_form"
      self.label = "Collect signed subscription form"
      self.workflowable_type = "DealingOrder"

      self.how = "The investor uploads the signed subscription form from their request, or an admin attaches it."
      self.why = "A subscription is dealt only against a signed form."
      self.effects = "The order moves on to acceptance. Nobody is emailed."

      def call(order)
        doc = order.subscription_form
        doc ? pass(message: "Signed form received", passed_since: doc.created_at) : fail_with(message: "Upload your signed subscription form", action_label: "Upload", action_path: order_path(order))
      end
    end
  end
end
