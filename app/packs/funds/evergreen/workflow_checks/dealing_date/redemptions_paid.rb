# Dealing-date journey check: Pay redemptions.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class RedemptionsPaid < WorkflowChecks::Base
      self.key = "dealing_date.redemptions_paid"
      self.label = "Pay redemptions"
      self.workflowable_type = "DealingDate"
      self.how = "Mark each redemption paid on the settlement tracker."
      self.why = "Redeeming investors are paid within the settlement days."
      self.effects = "Nothing is emailed until units are cancelled."

      def call(dealing_date)
        DealingProgress.new(dealing_date).redemptions_paid? ? pass(message: "All redemptions paid") : fail_with(message: "Mark each redemption paid")
      end
    end
  end
end
