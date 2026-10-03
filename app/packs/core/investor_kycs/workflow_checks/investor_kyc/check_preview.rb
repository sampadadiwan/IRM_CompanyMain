# 2. Preview the email — the second confirm task, and the one that catches a wrong placeholder: the
# preview renders THIS investor's copy (their name, the fund, their 30-day link), not the template.
# An acknowledge task like Set up KYC email, n/a under the same rule (ReviewNotNeeded).
#
# The second button runs the KYC page's own "Preview KYC Required Notification" item through
# action_target, because that item already opens in a new tab with the right template; action_path
# stays as the fallback the journey-action Stimulus controller uses when the item is not rendered.
# Worked examples H3, H4, H5, E8 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class CheckPreview < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.check_preview"
      self.label = "Preview the email (acknowledge)"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        # full_name is what InvestorKycMailer's "investor_name" placeholder renders, so the panel
        # names the investor exactly as the previewed email will address them
        WorkflowChecks::Result.review(
          message: "Preview the email as #{kyc.full_name} will receive it, then mark reviewed",
          action_label: "Preview KYC Required Notification", action_path: kyc_path(kyc),
          action_target: preview_button_id(kyc, KYC_REQUIRED_METHOD)
        )
      end
    end
  end
end
