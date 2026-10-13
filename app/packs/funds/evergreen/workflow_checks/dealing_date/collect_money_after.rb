# Dealing-date journey check: Collect subscription money after dealing.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class CollectMoneyAfter < WorkflowChecks::Base
      self.key = "dealing_date.collect_money_after"
      self.label = "Collect subscription money after dealing"
      self.workflowable_type = "DealingDate"
      self.how = "Record and verify payments on the settlement tracker."
      self.why = "Units are allotted when money is received."
      self.effects = "Nothing is emailed."

      def call(dealing_date)
        DealingProgress.new(dealing_date).money_collected_after? ? pass(message: "Every subscription paid") : fail_with(message: "Record and verify subscription payments")
      end
    end
  end
end
