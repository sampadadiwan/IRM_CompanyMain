# Dealing-date journey check: Review and confirm dealing.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class Confirm < WorkflowChecks::Base
      self.key = "dealing_date.confirm"
      self.label = "Review and confirm dealing"
      self.workflowable_type = "DealingDate"
      self.how = "Open the dealing date, review pricing and the gate, and click Confirm dealing."
      self.why = "Confirming fixes prices and settles orders."
      self.effects = "Gate notices and roll / cancel emails go to investors."

      def call(dealing_date)
        return pass(message: "Dealing confirmed") if DealingProgress.new(dealing_date).confirmed?

        # Decision 3: while a deadline is still open the step says which one, like the Confirm button
        fail_with(message: dealing_date.deadline_block_message || "Review pricing and the gate, then confirm")
      end
    end
  end
end
