# Dealing-date journey check: Send payment instructions.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class InstructionsSent < WorkflowChecks::Base
      self.key = "dealing_date.instructions_sent"
      self.label = "Send payment instructions"
      self.workflowable_type = "DealingDate"
      self.how = "Payment instructions are emailed when the dealing date is confirmed."
      self.why = "Subscribers need the exact amount and units to pay."
      self.effects = "Investors are emailed payment instructions."

      def call(dealing_date)
        DealingProgress.new(dealing_date).instructions_sent? ? pass(message: "Payment instructions sent") : fail_with(message: "Payment instructions not sent yet")
      end
    end
  end
end
