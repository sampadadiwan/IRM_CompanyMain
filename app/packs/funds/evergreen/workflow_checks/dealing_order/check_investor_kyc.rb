# Order journey check: Check investor KYC.
# Worked examples H12–H15, E19–E22 — openspec/changes/open-ended-funds/design.md#worked-examples
module WorkflowChecks
  module DealingOrder
    class CheckInvestorKyc < WorkflowChecks::Base
      include Support

      self.key = "dealing_order.check_investor_kyc"
      self.label = "Check investor KYC"
      self.workflowable_type = "DealingOrder"

      self.how = "Approve the investor's KYC (Compliance)."
      self.why = "Orders are dealt only for investors whose KYC is approved."
      self.effects = "The order moves on to the signed form. The investor isn't emailed."

      def call(order)
        if ::InvestorKyc.exists?(entity_id: order.entity_id, investor_id: order.investor_id, verified: true)
          pass(message: "KYC approved")
        else
          fail_with(message: "Waiting on the investor's KYC approval")
        end
      end
    end
  end
end
