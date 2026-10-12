# Dealing-date journey check: Collect subscription money.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class CollectMoney < WorkflowChecks::Base
      self.key = "dealing_date.collect_money"
      self.label = "Collect subscription money"
      self.workflowable_type = "DealingDate"
      self.how = "Record and verify subscribers' payments on the dealing date."
      self.why = "Funds paid before dealing deal only cleared money."
      self.effects = "Nothing is emailed."

      def call(dealing_date)
        DealingProgress.new(dealing_date).money_collected_before? ? pass(message: "Every subscription paid, or the cut-off passed") : fail_with(message: "Waiting for subscription money until the cut-off")
      end
    end
  end
end
