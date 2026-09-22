# Formatting for the entry page's "How this was worked out" card — see AccountEntryExplanation.
module AccountEntryExplanationHelper
  # A breakdown node's value as it should read. Currency only for what is known to be money —
  # formatting every figure as currency turned a year into "20.26". A recorded value that is not
  # a number at all (a date, a record) is shown as recorded.
  # @param node [AccountEntryExplanation::Node]
  # @param fund [Fund]
  # @return [String]
  def explanation_value(node, fund)
    number = node.numeric_value
    return node.value.to_s.truncate(40) if number.nil? && node.value.present?
    return "—" if number.nil?
    return money_to_currency(Money.new(number, fund.currency), params) if node.money?

    number_with_precision(number, precision: 6, strip_insignificant_zeros: true, delimiter: ",")
  end
end
