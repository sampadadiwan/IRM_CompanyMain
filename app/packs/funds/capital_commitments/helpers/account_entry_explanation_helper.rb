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

  # A recorded step's value as it reads in the calculation steps table: long decimals rounded to
  # two places, rationals ("89/1") worked out, thousands separated. Dates, records and text are
  # left as recorded. Not currency: a step's value is whatever the rule computed — a rate, a
  # count, a sum of cents — and nothing in the recording says which.
  # @param value [Object] as recorded in the entry's explanation breakdown
  # @return [String]
  def explanation_step_value(value)
    text = value.to_s.strip
    number = if text.match?(%r{\A-?\d+/\d+\z})
               # A rational: "89/1" -> 89.
               numerator, denominator = text.split("/").map(&:to_d)
               denominator.zero? ? nil : numerator / denominator
             elsif text.match?(/\A-?\d+(\.\d+)?\z/)
               text.to_d
             end
    return text if number.nil?

    # Whole numbers without decimals; anything else to two places.
    precision = number == number.truncate ? 0 : 2
    number_with_precision(number, precision: precision, delimiter: ",")
  end
end
