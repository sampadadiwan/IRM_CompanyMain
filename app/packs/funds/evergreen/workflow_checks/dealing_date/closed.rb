# Dealing-date journey check: Close dealing date.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class Closed < WorkflowChecks::Base
      self.key = "dealing_date.closed"
      self.label = "Close dealing date"
      self.workflowable_type = "DealingDate"
      self.how = "Click Close dealing date."
      self.why = "Closing marks the dealing date done."
      self.effects = "Nothing is emailed."

      def call(dealing_date)
        DealingProgress.new(dealing_date).closed? ? pass(message: "Closed") : fail_with(message: "Close the dealing date once everything settled")
      end
    end
  end
end
