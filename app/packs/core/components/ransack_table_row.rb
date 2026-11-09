class RansackTableRow < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include CurrencyHelper

  # The stored forms a Boolean column's value may take (custom fields hold strings such as "Yes" / "1" / "0")
  TRUE_VALUES = %w[true yes y 1 t on].freeze
  FALSE_VALUES = %w[false no n 0 f off].freeze

  def initialize(model:, columns:)
    super()
    @columns = columns
    @model = model
  end

  # The value of a column marked Boolean as true / false, or nil when it is blank or not a recognisable boolean
  # (then the cell shows the raw value rather than a misleading "No")
  def boolean_value(value)
    # Real booleans need no casting
    return value if [true, false].include?(value)

    # Strings and numbers: compare their normalised text with the known true / false forms
    text = value.to_s.strip.downcase
    return true if TRUE_VALUES.include?(text)
    return false if FALSE_VALUES.include?(text)

    nil
  end
end
