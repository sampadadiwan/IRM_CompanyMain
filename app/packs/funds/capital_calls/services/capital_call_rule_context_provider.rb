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
#
# Both keys return nil when there are no remittances so that the rules evaluate to "not triggered"
# rather than incorrectly flagging a call that simply hasn't had remittances generated yet.
class CapitalCallRuleContextProvider
  # @param record [CapitalCall]  The call being validated (must be persisted for DB lookups)
  # @param entity [Entity]       Unused here but part of the standard provider interface
  # @param params [Hash]         Unused — no parameterised queries for these rules
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    # Both rules are only meaningful for persisted calls that have generated remittances.
    # A new/unsaved call or one with no remittances returns nil for both keys so rules don't fire.
    return default_context unless record.persisted?

    remittance_ids = record.capital_remittance_ids
    return default_context if remittance_ids.empty?

    {
      remittances_without_notices: remittances_without_notices(remittance_ids),
      unapproved_notices_count: unapproved_notices_count(remittance_ids)
    }
  end

  private

  def default_context
    { remittances_without_notices: nil, unapproved_notices_count: nil }
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
end
