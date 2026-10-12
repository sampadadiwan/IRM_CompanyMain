# Dealing-date journey skip: Skip: no subscriptions.
module WorkflowChecks
  module DealingDate
    class NoSubscriptions < WorkflowChecks::Base
      self.key = "dealing_date.no_subscriptions"
      self.label = "Skip: no subscriptions"
      self.workflowable_type = "DealingDate"

      def call(dealing_date)
        DealingProgress.new(dealing_date).subscriptions? ? fail_with(message: "Applies") : pass(message: "No subscriptions on this dealing date")
      end
    end
  end
end
