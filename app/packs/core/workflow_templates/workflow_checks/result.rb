# The answer a check gives about one task: is it done, what should the panel say, where can the
# user go to fix it, and when did the evidence appear.
#
# action_path   — where the panel's button goes (another screen, or this record's own page).
# action_target — the DOM id of the control on the record's OWN page that actually does this task
#                 ("capital_call_notify_btn"), or a "#tab-id" to open. The panel's button clicks it
#                 instead of navigating, so the user does not land back on the page they are on.
#                 Purely presentational: the panel falls back to action_path when it is not there.
#
# passed_since — when the task became true (the NEWEST evidence: a task passes when its last
#                missing piece arrives). Used to stamp history and "current since" from the data.
# fresh_since  — the OLDEST evidence the check relied on. Used only after an invalidation: one
#                stale piece is enough to fail, so all evidence must be newer than the invalidation.
#
# review       — acknowledge steps only, opt-in (nil keeps today's behaviour: a passing check just
#                offers "Mark reviewed" with "Not confirmed yet"):
#                :confirmed — the record's data already confirms the step (e.g. AI validated every
#                             document), so it passes with no click — if newer than any invalidation;
#                :requested — still needs "Mark reviewed", but show this check's message and offer its
#                             action as a second button (e.g. "Open validation").
# new_tab      — :requested only: open that second button in a new tab, for a page the user reads and
#                comes back from (e.g. the call's custom notification) rather than one where they act.
# Worked examples H5, E3 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  Result = Data.define(:passed, :message, :action_label, :action_path, :action_target, :passed_since, :fresh_since, :review, :new_tab) do
    # The task is done
    def self.pass(message: nil, passed_since: nil, fresh_since: nil, action_label: nil, action_path: nil, action_target: nil)
      new(passed: true, message:, action_label:, action_path:, action_target:, passed_since:, fresh_since: fresh_since || passed_since, review: nil, new_tab: false)
    end

    # The task is not done yet; message tells the user what is missing
    def self.fail(message:, action_label: nil, action_path: nil, action_target: nil)
      new(passed: false, message:, action_label:, action_path:, action_target:, passed_since: nil, fresh_since: nil, review: nil, new_tab: false)
    end

    # Acknowledge step: the data confirms it, no "Mark reviewed" needed
    def self.confirmed(message:, passed_since: nil, fresh_since: nil)
      new(passed: true, message:, action_label: nil, action_path: nil, action_target: nil, passed_since:,
          fresh_since: fresh_since || passed_since, review: :confirmed, new_tab: false)
    end

    # Acknowledge step: needs "Mark reviewed"; the panel shows this message and this action beside it
    def self.review(message:, action_label: nil, action_path: nil, action_target: nil, new_tab: false)
      new(passed: true, message:, action_label:, action_path:, action_target:, passed_since: nil, fresh_since: nil,
          review: :requested, new_tab:)
    end

    alias_method :passed?, :passed
  end
end
