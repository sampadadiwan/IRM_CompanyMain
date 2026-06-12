# Provides named context values for CapitalRemittance send-notification rules.
# Scoped to the single remittance being acted on, unlike CapitalCallRuleContextProvider
# which checks all remittances in the call.
#
# Context keys returned:
#   notice_not_generated  — truthy when this remittance has no generated call notice document.
#                           nil when a generated document exists (rule should not fire).
#   notice_not_approved   — count of generated documents pending approval for this remittance.
#                           nil when all generated notices are approved (rule should not fire).
class CapitalRemittanceRuleContextProvider
  # @param record [CapitalRemittance]  The remittance being validated (must be persisted)
  # @param entity [Entity]             Unused but part of the standard provider interface
  # @param params [Hash]               Unused
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    return default_context unless record.persisted?

    {
      notice_not_generated: notice_not_generated(record.id),
      notice_not_approved: notice_not_approved(record.id)
    }
  end

  private

  def default_context
    { notice_not_generated: nil, notice_not_approved: nil }
  end

  # Returns true when the remittance has no document with owner_tag "Generated"; nil otherwise.
  def notice_not_generated(remittance_id)
    has_notice = Document.exists?(owner_type: "CapitalRemittance",
                                  owner_id: remittance_id,
                                  owner_tag: "Generated")

    has_notice ? nil : true
  end

  # Returns the count of generated documents not yet approved; nil when all are approved.
  def notice_not_approved(remittance_id)
    count = Document.where(
      owner_type: "CapitalRemittance",
      owner_id: remittance_id,
      owner_tag: "Generated",
      approved: false
    ).count

    count.positive? ? count : nil
  end
end
