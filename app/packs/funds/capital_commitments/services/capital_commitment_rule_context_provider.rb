# Provides named context values for CapitalCommitment rules.
#
# Context keys returned:
#   investor_without_subscribers — the investor's name when nobody at that investor is subscribed
#                                  to Capital Call notifications for the commitment's fund
#                                  (Investor#capital_call_subscribers?); nil otherwise.
#
# Business rationale (docs/user_guides/capital_call_actions_and_notifications_matrix.md,
# Question 6): a fund manager should learn about a missing subscription the moment an investor is
# added to a fund, not months later when a Send Call Notification button greys out. Running it
# through the rule engine (rather than a hard-coded controller check) keeps it consistent with the
# Approve-time check and lets a company admin switch it off for a fund that notifies investors
# some other way.
class CapitalCommitmentRuleContextProvider
  # @param record [CapitalCommitment]  The commitment being validated
  # @param entity [Entity]             Unused here but part of the standard provider interface
  # @param params [Hash]               Unused — no parameterised queries for this rule
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    { investor_without_subscribers: investor_without_subscribers(record) }
  end

  private

  def investor_without_subscribers(record)
    return nil if record.investor.nil? || record.fund.nil?
    # A skip_doc_gen commitment is excluded from every send path by design, so a missing
    # subscription changes nothing for it — mirrors CapitalCallRuleContextProvider.
    return nil if record.skip_doc_gen?
    return nil if record.investor.capital_call_subscribers?(record.fund)

    record.investor.investor_name
  end
end
