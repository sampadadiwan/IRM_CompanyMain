# Which of the LP's four push categories a notification belongs to (lp-mobile-app design card ⑥).
#
# Keyed by notifier class, with one record-type refinement for reminders. A notifier not listed
# here falls into "other" (E12), so a new notifier is pushed under "Everything else" until it is
# given a category — never silently dropped.
module MobilePushCategory
  BY_NOTIFIER = {
    "CapitalRemittanceNotifier" => "capital_calls",
    "CapitalRemittancePaymentNotifier" => "capital_calls",
    "CapitalDistributionPaymentNotifier" => "distributions",
    "DocumentNotifier" => "documents",
    "NdaEventNotifier" => "documents",
    "NdaReminderNotifier" => "documents",
    "FinancialStatementNotifier" => "documents"
  }.freeze

  module_function

  # @param event [Noticed::Event, nil]
  def for(event)
    return "other" if event.nil?
    # A reminder about a capital call is a capital-call alert
    return "capital_calls" if event.type == "ReminderNotifier" && event.record_type == "CapitalRemittance"

    BY_NOTIFIER.fetch(event.type, "other")
  end

  # Has the user left this notification's category switched on? (E10; default on)
  def enabled_for?(user, event)
    user.push_preferences.fetch(self.for(event), true)
  end
end
