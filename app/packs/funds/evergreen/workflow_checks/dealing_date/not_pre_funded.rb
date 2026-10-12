# Dealing-date journey skip: Skip: not paid before dealing.
module WorkflowChecks
  module DealingDate
    class NotPreFunded < WorkflowChecks::Base
      self.key = "dealing_date.not_pre_funded"
      self.label = "Skip: not paid before dealing"
      self.workflowable_type = "DealingDate"

      def call(dealing_date)
        if !dealing_date.pre_funded? || !DealingProgress.new(dealing_date).subscriptions?
          pass(message: dealing_date.pre_funded? ? "No subscriptions on this dealing date" : "This fund takes subscription money after dealing")
        else
          fail_with(message: "Applies")
        end
      end
    end
  end
end
