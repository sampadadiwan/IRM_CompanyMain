# 2. Submit KYC — the investor submitted it, or a fund user ticked "complete" (completed), or it is
# verified. The message says where it is waiting.
# Worked examples H4, H9 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class Submit < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.submit"
      self.label = "Submit KYC"
      self.workflowable_type = "InvestorKyc"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Wait for the investor, or nudge them with Send KYC Reminder."
      self.why = "Nothing can be checked until the details are in."
      self.effects = "When the investor submits, your team is notified. Send KYC Reminder emails the investor again."

      def call(kyc)
        return pass(message: "KYC submitted", passed_since: kyc.submitted_at) if submitted?(kyc)

        case kyc.submission_status
        when "draft_saved"
          saved = kyc.investor_user_updated_at || kyc.updated_at
          fail_with(message: "The investor saved a draft on #{date(saved)} but has not submitted",
                    action_label: "Send KYC Reminder", action_path: kyc_path(kyc), action_target: email_button_id(kyc, "kyc_required_reminder"))
        when "link_sent"
          fail_with(message: "Waiting for the investor — form sent on #{date(kyc.link_sent_at || kyc.updated_at)}",
                    action_label: "Send KYC Reminder", action_path: kyc_path(kyc), action_target: email_button_id(kyc, "kyc_required_reminder"))
        else
          fail_with(message: "Not submitted yet — fill it in and tick complete",
                    action_label: "Edit", action_path: edit_kyc_path(kyc), action_target: EDIT_BTN)
        end
      end
    end
  end
end
