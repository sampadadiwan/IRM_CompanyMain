# Business rationale (docs/user_guides/capital_call_actions_and_notifications_matrix.md,
# Question 3): after a call correction, or when a Call Notice bounced, the remittance's
# "Notification Sent" flag has to be reset by hand — and until now that meant an engineer at the
# Rails console or someone un-ticking it on one Edit Remittance screen at a time. This op is the
# model-layer half of the bulk "Mark Notification Sent / Unsent" actions on the remittance search
# page, so the business team can self-serve.
#
# The two actions are deliberately idempotent set-to-a-value operations rather than a toggle: a
# blind toggle over a mixed search result (45 already-sent, 5 never-sent) would silently flip the
# 5 TO sent and hide them from the next Send Notification.
class CapitalRemittanceSetNotificationSent < CapitalRemittanceAction
  step :set_notification_sent

  # update_column, not save: the flag drives no status/counter/fee computation (unlike verified),
  # the only other writer (CapitalRemittance#send_notification) already uses update_column, and a
  # full save would (a) refuse to reset the flag on legacy rows that fail today's validations —
  # exactly the rows this self-service action exists for — and (b) write an audit row, touch the
  # fund and reindex for every one of potentially hundreds of remittances.
  def set_notification_sent(_ctx, capital_remittance:, notification_sent:, **)
    capital_remittance.update_column(:notification_sent, notification_sent) # rubocop:disable Rails/SkipsModelValidations
    true
  end
end
