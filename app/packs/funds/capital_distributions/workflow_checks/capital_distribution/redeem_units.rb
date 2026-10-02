# 9. Redeem units — every completed payment that can redeem units has fund units. "Can" mirrors
# DefaultUnitAllocationEngine#allocate_distribution_payment: completed, a face value for redemption
# (cost_of_investment_with_fees) above zero, and a unit type on the commitment.
# Worked examples H8, E13 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class RedeemUnits < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.redeem_units"
      self.label = "Redeem units"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        redeemable = payments(dist).where(completed: true).where("capital_distribution_payments.cost_of_investment_with_fees_cents > 0")
                                   .joins(:capital_commitment).where.not(capital_commitments: { unit_type: [nil, ""] })
        units = ::FundUnit.where(owner_type: "CapitalDistributionPayment", owner_id: redeemable.select(:id))
        total = redeemable.count
        without = redeemable.where.not(id: units.select(:owner_id)).count
        # Units are redeemed against completed payments only: say so rather than "0 of 0"
        return fail_with(message: "Units are redeemed once every payment is marked completed") unless completed_all?(dist)
        return pass(message: total.zero? ? "No units to redeem" : "Units redeemed", passed_since: units.maximum(:created_at)) if without.zero?

        fail_with(message: "#{total - without} of #{total} payments have redeemed units", action_label: "Redeem Units",
                  action_path: distribution_path(dist), action_target: REDEEM_UNITS_BTN)
      end

      private

      # Units are redeemed against completed payments only, so the task can't be done while some
      # payment is still to be completed
      def completed_all?(dist)
        payments(dist).exists? && !payments(dist).exists?(completed: false)
      end
    end
  end
end
