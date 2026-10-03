# Skip check for the two email tasks ("Set up KYC email", "Preview the email"): there is nothing
# left to review once the email can no longer be changed — the form has gone out, or the fund filled
# the KYC in itself and no email is going anywhere. A review after sending cannot change what the
# investor received, so it must never hold the journey up (capital-call-journey design Decision 15,
# the same rule CapitalCall::ReviewNotNeeded applies to notices).
# Worked examples E1, E2, E8, E11 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class ReviewNotNeeded < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.review_not_needed"
      self.label = "Skip: the KYC form has already been sent"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        # Checked first: a fund-filled KYC satisfies both conditions, and this is the better reason
        return pass(message: "Filled in by the fund") if FilledByFund.new.call(kyc).passed?

        # The same data SendForm treats as sent, so the email tasks can never still be asking for
        # attention while "Send KYC form" shows as done
        return pass(message: "The KYC form has already been sent") if form_sent?(kyc)

        fail_with(message: "Review needed")
      end

      private

      # The link was emailed, or the investor has started or submitted the form (an imported KYC
      # arrives already past "not_sent")
      def form_sent?(kyc)
        kyc.link_sent_at.present? || kyc.submission_status != "not_sent"
      end
    end
  end
end
