# Dealing-date journey check: Approve NAV.
# Worked examples H17, H21, H24, E23 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingDate
    class ApproveNav < WorkflowChecks::Base
      self.key = "dealing_date.approve_nav"
      self.label = "Approve NAV"
      self.workflowable_type = "DealingDate"
      self.how = "Draft the NAV and have a user with the approver role approve it."
      self.why = "Every order is priced at an approved NAV."
      self.effects = "Nothing is emailed."

      def call(dealing_date)
        DealingProgress.new(dealing_date).nav_approved? ? pass(message: "NAV approved") : fail_with(message: "Approve the NAV for every class with orders")
      end
    end
  end
end
