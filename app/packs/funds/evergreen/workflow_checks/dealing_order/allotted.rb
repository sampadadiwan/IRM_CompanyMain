# Order journey check: Allot units and send contract note.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class Allotted < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.allotted"
      self.label = "Allot units and send contract note"
      self.workflowable_type = "DealingOrder"

      self.how = "Units are allotted automatically once the dealing date is confirmed and the money is in."
      self.why = "The investor owns units only once they are allotted."
      self.effects = "The investor is emailed the contract note."

      def call(order)
        fill = fill_for(order)
        fill&.fund_unit_id && fill.document_sent_at ? pass(message: "Units allotted") : fail_with(message: "Units not allotted yet")
      end
    end
  end
end
