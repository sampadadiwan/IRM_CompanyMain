# 7. Mark payments completed — the distribution has payments and none is incomplete. Comes before
# Email investors: only a completed payment is emailed (design Key idea 3).
# Worked examples H6, E9 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class CompletePayments < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.complete_payments"
      self.label = "Mark payments completed"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        total = payments(dist).count
        completed = payments(dist).where(completed: true).count
        return pass(message: "#{total} #{'payment'.pluralize(total)} completed", passed_since: payments(dist).maximum(:updated_at)) if total.positive? && completed == total

        fail_with(message: "#{completed} of #{total} payments marked completed", action_label: "Mark Payments Completed",
                  action_path: distribution_path(dist), action_target: PAYMENTS_COMPLETED_BTN)
      end
    end
  end
end
