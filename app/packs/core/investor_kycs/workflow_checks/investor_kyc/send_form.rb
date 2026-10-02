# 1. Send KYC form — the form link has been sent to the investor (or the investor already has it:
# they started or submitted it). n/a when the fund filled it in itself (FilledByFund).
# Worked examples H2, H3 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class SendForm < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.send_form"
      self.label = "Send KYC form"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        return pass(message: "KYC form sent", passed_since: kyc.link_sent_at) if kyc.link_sent_at.present? || kyc.submission_status != "not_sent"

        # The send action needs someone at the investor to email (InvestorKycsController#notify_kyc_required)
        unless kyc.investor&.approved_users&.exists?
          return fail_with(message: "The investor has no users to send the form to — add one, or fill it in yourself",
                           action_label: "Edit", action_path: edit_kyc_path(kyc), action_target: EDIT_BTN)
        end

        fail_with(message: "The KYC form has not been sent — send it, or fill it in and tick complete",
                  action_label: "Send KYC Required Notification", action_path: kyc_path(kyc),
                  action_target: email_button_id(kyc, "notify_kyc_required"))
      end
    end
  end
end
