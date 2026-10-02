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
