# 8. Send notices — no notifiable remittance is unsent. notification_sent is written with
# update_column (no timestamp), so the pass time falls back to when it was noticed.
# Worked examples H5, E28 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class SendNotices < WorkflowChecks::Base
      include Support

      self.key = "capital_call.send_notices"
      self.label = "Send notices"
      self.workflowable_type = "CapitalCall"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Click Send Notification."
      self.why = "The notice is the investor's formal demand for the money; investors with nobody subscribed are flagged on the panel."
      self.effects = "Every subscribed investor is emailed their notice (and WhatsApp, if enabled). Emails can't be recalled."

      def call(call)
        notifiable = notifiable_remittances(call)
        unsent = notifiable.where(notification_sent: false).count
        return pass(message: "#{notifiable.count} notices sent") if notifiable.exists? && unsent.zero?

        fail_with(message: "#{unsent} #{'notice'.pluralize(unsent)} not yet sent", action_label: "Send Notification",
                  action_path: call_path(call), action_target: NOTIFY_BTN)
      end
    end
  end
end
