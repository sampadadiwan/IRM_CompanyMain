# Dealing-date journey skip: Skip: not paid after dealing.
module WorkflowChecks
  module DealingDate
    class NotPayAfter < WorkflowChecks::Base
      self.key = "dealing_date.not_pay_after"
      self.label = "Skip: not paid after dealing"
      self.workflowable_type = "DealingDate"

      def call(dealing_date)
        if dealing_date.pre_funded? || !DealingProgress.new(dealing_date).subscriptions?
          pass(message: dealing_date.pre_funded? ? "This fund takes subscription money before dealing (by the cut-off)" : "No subscriptions on this dealing date")
        else
          fail_with(message: "Applies")
        end
      end
    end
  end
end
