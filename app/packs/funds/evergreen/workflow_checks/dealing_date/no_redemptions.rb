# Dealing-date journey skip: Skip: no redemptions.
module WorkflowChecks
  module DealingDate
    class NoRedemptions < WorkflowChecks::Base
      self.key = "dealing_date.no_redemptions"
      self.label = "Skip: no redemptions"
      self.workflowable_type = "DealingDate"

      def call(dealing_date)
        DealingProgress.new(dealing_date).redemptions? ? fail_with(message: "Applies") : pass(message: "No redemptions on this dealing date")
      end
    end
  end
end
