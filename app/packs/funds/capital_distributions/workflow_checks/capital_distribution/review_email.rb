# 4. Review custom notification — an acknowledge task: what makes it done is the person's "Mark
# reviewed". This check names the distribution email investors will actually receive and offers the
# way to read it, or to create one.
#
# The email is the payment notice (email_method send_notification), resolved exactly as the mailer
# does (CapitalDistribution#custom_notification): the distribution's own override first, then the
# fund's default for distributions. With neither, CapHive's built-in text is sent.
#
# Result.review (not pass) is what makes the panel show this message and a second button beside
# "Mark reviewed" — the same mechanism as the capital call's step.
# Worked examples H4, E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class ReviewEmail < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.review_email"
      self.label = "Review custom notification (acknowledge)"
      self.workflowable_type = "CapitalDistribution"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Read the email text investors will receive, then click Mark reviewed."
      self.why = "The wording comes from the distribution's or the fund's custom notification, or CapHive's default when neither exists."
      self.effects = "Records who reviewed it. No emails are sent. Editing the notification afterwards reopens this step."

      DISTRIBUTION_EMAIL_METHOD = "send_notification".freeze

      def call(dist)
        notification = dist.custom_notification(DISTRIBUTION_EMAIL_METHOD)

        # A notification exists: name it by subject (what investors see) and say where it is set,
        # then open it in a new tab so the journey stays put while it is read
        if notification
          level = notification.owner_type == "CapitalDistribution" ? "set on this distribution" : "the fund's default"
          return WorkflowChecks::Result.review(
            message: "Distribution email \"#{notification.subject}\" (#{level}) will be sent — check it and mark reviewed",
            action_label: "View notification", action_path: routes.custom_notification_path(notification), new_tab: true
          )
        end

        # None: CapHive's default text goes out, so say so and offer the distribution's "New
        # Distribution Notification" form. Marking reviewed accepts the default.
        WorkflowChecks::Result.review(
          message: "No custom notification is set up — CapHive's default distribution email will be sent. " \
                   "Create one, or mark reviewed to use the default",
          action_label: "New Distribution Notification", action_path: new_distribution_notification_path(dist)
        )
      end
    end
  end
end
