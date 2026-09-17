# Provides named context values for CapitalCall approval rules.
#
# Context keys returned:
#   remittances_without_notices  — comma-separated investor names whose remittances have no
#                                  generated document (owner_tag: "Generated").
#                                  nil when the call has no remittances (rule not applicable).
#                                  nil when all remittances have at least one generated notice.
#   unapproved_notices_count     — number of generated documents that are not yet approved.
#                                  nil when the call has no remittances (rule not applicable).
#                                  nil when all generated notices are approved.
#   investors_without_notification_subscribers — comma-separated names of investors on this call
#                                  with nobody subscribed to Capital Call notifications (mirrors
#                                  CapitalRemittance#notification_blocked_reasons). nil when the
#                                  call has no remittances, or when every investor has at least
#                                  one subscriber. Surfaces the gap proactively at Approve time —
#                                  see docs/user_guides/capital_call_actions_and_notifications_matrix.md,
#                                  Open Question 6 — instead of only reactively, one grey-out at a
#                                  time, when someone actually tries to send.
#
# All keys return nil when there are no remittances so that the rules evaluate to "not triggered"
# rather than incorrectly flagging a call that simply hasn't had remittances generated yet.
class CapitalCallRuleContextProvider
  # @param record [CapitalCall]  The call being validated (must be persisted for DB lookups)
  # @param entity [Entity]       Unused here but part of the standard provider interface
  # @param params [Hash]         Unused — no parameterised queries for these rules
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    # All rules are only meaningful for persisted calls that have generated remittances.
    # A new/unsaved call or one with no remittances returns nil for every key so rules don't fire.
    return default_context unless record.persisted?

    remittance_ids = record.capital_remittance_ids
    return default_context if remittance_ids.empty?

    {
      remittances_without_notices: remittances_without_notices(remittance_ids),
      unapproved_notices_count: unapproved_notices_count(remittance_ids),
      investors_without_notification_subscribers: investors_without_notification_subscribers(record)
    }
  end

  private

  def default_context
    { remittances_without_notices: nil, unapproved_notices_count: nil, investors_without_notification_subscribers: nil }
  end

  # Returns a comma-separated list of investor_name values for remittances that have
  # NO document with owner_tag "Generated". Returns nil when all remittances have a notice.
  def remittances_without_notices(remittance_ids)
    with_notice_ids = Document
                      .where(owner_type: "CapitalRemittance", owner_id: remittance_ids, owner_tag: "Generated")
                      .distinct
                      .pluck(:owner_id)
                      .to_set

    missing_ids = remittance_ids.reject { |id| with_notice_ids.include?(id) }
    return nil if missing_ids.empty?

    CapitalRemittance.where(id: missing_ids).pluck(:investor_name).join(", ")
  end

  # Returns the count of generated (owner_tag "Generated") documents that are not approved,
  # or nil when all generated notices are approved (rule should not fire).
  def unapproved_notices_count(remittance_ids)
    count = Document
            .where(owner_type: "CapitalRemittance", owner_id: remittance_ids,
                   owner_tag: "Generated", approved: false)
            .count

    count.positive? ? count : nil
  end

  # The Approve flash is stored in the cookie session (4KB hard limit), so the name list is
  # capped — a freshly imported fund routinely has every investor unsubscribed.
  MAX_NAMES_IN_MESSAGE = 10

  # Returns a comma-separated list of investor_name values for investors on this call who have
  # nobody subscribed to receive Capital Call notifications (Investor#capital_call_subscribers?).
  # Returns nil when every investor on the call has at least one subscriber.
  #
  # Commitments flagged skip_doc_gen are excluded: every send path (call-level notify, per-remittance
  # send, and the reminder) skips them by design, so telling the fund manager to subscribe a
  # contact for one would be a false positive.
  def investors_without_notification_subscribers(record)
    # skip_doc_gen lives in the commitment's json_fields, so it has to be filtered in Ruby.
    # capital_remittances is a very wide table — pull only the two foreign keys needed here.
    investor_ids = record.capital_remittances
                         .select(:id, :investor_id, :capital_commitment_id)
                         .includes(:capital_commitment)
                         .reject { |cr| cr.capital_commitment.skip_doc_gen? }
                         .map(&:investor_id)
                         .uniq
    return nil if investor_ids.empty?

    # Cheap set-based pre-filter: an investor with no approved contact whose tag_list admits
    # CapitalCall cannot be subscribed, whatever the fund policy says — so the per-contact Pundit
    # check in capital_call_subscribers? is only run for investors who have at least one
    # candidate contact. Tag semantics mirror Investor#notification_users (blank tag_list =
    # subscribed to everything).
    candidate_ids = InvestorAccess.approved
                                  .where(investor_id: investor_ids)
                                  .where("investor_accesses.tag_list IS NULL OR investor_accesses.tag_list = '' OR investor_accesses.tag_list LIKE ?", "%CapitalCall%")
                                  .distinct
                                  .pluck(:investor_id)

    unsubscribed_ids = investor_ids - candidate_ids
    unsubscribed_ids += Investor.where(id: candidate_ids).reject { |investor| investor.capital_call_subscribers?(record.fund) }.map(&:id)
    return nil if unsubscribed_ids.empty?

    names = Investor.where(id: unsubscribed_ids).order(:investor_name).limit(MAX_NAMES_IN_MESSAGE).pluck(:investor_name)
    overflow = unsubscribed_ids.size - names.size
    overflow.positive? ? "#{names.join(', ')} and #{overflow} more" : names.join(", ")
  end
end
