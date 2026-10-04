# 1. Set up KYC email — the first task of the journey, and the first thing standing between a new
# KYC and the investor's inbox. An acknowledge task: what completes it is the person's "Mark
# reviewed"; this check names the email that will actually be sent and offers the way to change it.
# n/a once the form has gone out, or the fund filled the KYC in itself (ReviewNotNeeded).
#
# Result.review (not pass) is what makes the panel show this message and a second button beside
# "Mark reviewed" — the same mechanism ValidateDocuments uses.
# Worked examples H1, H2, H3, E8, E14 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class ReviewEmail < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.review_email"
      self.label = "Set up KYC email (acknowledge)"
      self.workflowable_type = "InvestorKyc"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Check the KYC email the investor will receive, then click Mark reviewed."
      self.why = "It's the investor's first contact about KYC; the company's own email is used, or CapHive's default when there is none."
      self.effects = "Records who reviewed it. No emails are sent."

      def call(kyc)
        notification = kyc_required_notification(kyc)

        # The company has its own KYC email: name it by subject, which is what the investor sees as
        # the email's subject (ApplicationMailer#send_mail swaps in the notification's subject)
        if notification
          return WorkflowChecks::Result.review(
            message: "Your KYC email \"#{notification.subject}\" will be sent — check it and mark reviewed",
            # The notification itself, in a new tab so the journey stays put while it is read
            # (same as the call's and distribution's "Review custom notification")
            action_label: "View notification", action_path: routes.custom_notification_path(notification), new_tab: true
          )
        end

        # No company email: CapHive's default text goes out under the fund's name, so say so and
        # offer the form that creates one. Marking reviewed accepts the default.
        WorkflowChecks::Result.review(
          message: "No KYC email is set up — CapHive's default text will be sent. " \
                   "Set one up, or mark reviewed to use the default",
          action_label: "Custom KYC Notification", action_path: new_kyc_notification_path(kyc)
        )
      end
    end
  end
end
