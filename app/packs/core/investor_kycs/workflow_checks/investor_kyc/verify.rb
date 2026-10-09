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
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Click Verify."
      self.why = "Only verified KYCs get call and distribution notices, so this unblocks the investor everywhere."
      self.effects = "The KYC is verified, so this investor's call and distribution notices are no longer blocked. The investor is not emailed."
      self.closes_journey = true
      self.closing_note = "Verified without this step"

      def call(kyc)
        return pass(message: "KYC verified", passed_since: verified_at(kyc)) if kyc.submission_status == "verified"

        fail_with(message: "Not verified yet", action_label: "Verify", action_path: kyc_path(kyc), action_target: VERIFY_BTN)
      end
    end
  end
end
