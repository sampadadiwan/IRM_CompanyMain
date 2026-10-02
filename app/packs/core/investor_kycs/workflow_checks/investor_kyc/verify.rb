# 9. Verify KYC — the KYC is verified. A closing check: once verified, every earlier task that isn't
# done shows "Verified without this step", so an imported verified KYC (or one verified early) has a
# complete journey; UnVerify reopens them.
# Worked examples H8, E6, E11 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class Verify < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.verify"
      self.label = "Verify KYC"
      self.workflowable_type = "InvestorKyc"
      self.closes_journey = true
      self.closing_note = "Verified without this step"

      def call(kyc)
        return pass(message: "KYC verified", passed_since: verified_at(kyc)) if kyc.submission_status == "verified"

        fail_with(message: "Not verified yet", action_label: "Verify", action_path: kyc_path(kyc), action_target: VERIFY_BTN)
      end
    end
  end
end
