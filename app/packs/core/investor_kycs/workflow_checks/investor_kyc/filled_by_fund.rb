# Skip check for "Send KYC form": the KYC was submitted (or verified) without a form link ever being
# sent, so the fund filled it in itself.
# Worked examples H9 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class FilledByFund < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.filled_by_fund"
      self.label = "Filled in by the fund"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        return pass(message: "Filled in by the fund") if submitted?(kyc) && kyc.link_sent_at.nil?

        fail_with(message: "A form was sent")
      end
    end
  end
end
