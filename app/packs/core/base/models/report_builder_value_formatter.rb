# Turns a Report Builder value into what people see, by the column's type —
# the same rules for the builder preview, the report page and the Excel export:
#   money / number  separators + 2 decimals, right-aligned; currency label on money when set
#   integer         separators, no decimals (counts)
#   date / time     the user's locale format (I18n.l); real date cells in Excel
#   yes/no          "Yes" / "No"
#   text            as is
# Indian digit grouping (5,00,00,000) when the report's currency — or, if none
# is set, the entity's — is INR, as CurrencyHelper does for crores/lakhs.
#
# Worked examples H15, H16, E15, E16, X6 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderValueFormatter
  NUMERIC_TYPES = %i[money number integer].freeze
  TRUE_VALUES   = [true, 1, "1", "true", "t", "TRUE"].freeze
  FALSE_VALUES  = [false, 0, "0", "false", "f", "FALSE"].freeze
  EXCEL_DATE     = "dd-mmm-yyyy".freeze
  EXCEL_DATETIME = "dd-mmm-yyyy hh:mm".freeze

  def initialize(config:, entity: nil)
    @config      = config
    @column_type = config.column_type
    @india       = (config.currency.presence || entity&.currency).to_s.upcase == "INR"
  end

  # Text for the screen (escaped by the view like any string)
  def display(value, column)
    return "" if value.nil?

    case type_of(value, column)
    when :money   then "#{currency_prefix(column)}#{number(value, 2)}"
    when :number  then number(value, 2)
    when :integer then number(value, 0)
    when :date    then localize(to_date(value))
    when :datetime then localize(to_time(value))
    when :boolean then yes_no(value)
    else value.to_s
    end
  end

  # Bootstrap class for the cell: numbers line up on the right
  def align(column)
    NUMERIC_TYPES.include?(column_type.type_for(column)) ? "text-end" : ""
  end

  # [cell value, Excel number format or nil] — numbers and dates stay real
  # numbers and dates in Excel, so sorting and SUM work there
  def xlsx(value, column)
    return [nil, nil] if value.nil?

    case type_of(value, column)
    when :money   then [decimal(value), money_format(column)]
    when :number  then [decimal(value), "#,##0.00"]
    when :integer then [decimal(value), "#,##0"]
    when :date    then [to_date(value), EXCEL_DATE]
    when :datetime then [to_time(value), EXCEL_DATETIME]
    when :boolean then [yes_no(value), nil]
    else [value.to_s, nil]
    end
  end

  # The column's type, or — for method-only columns whose type isn't known
  # in advance — the value's own kind (X6: anything else reads as text)
  def type_of(value, column)
    type = column_type.type_for(column)
    return type unless type == :unknown

    case value
    when Money, BigDecimal, Float then :number
    when Integer then :integer
    when Date then value.is_a?(DateTime) ? :datetime : :date
    when Time, ActiveSupport::TimeWithZone then :datetime
    when true, false then :boolean
    else :text
    end
  end

  private

  attr_reader :config, :column_type

  def number(value, precision)
    rounded = ActiveSupport::NumberHelper.number_to_rounded(decimal(value), precision: precision)
    if @india
      ActiveSupport::NumberHelper.number_to_delimited(rounded, delimiter_pattern: CurrencyHelper::INDIA_FORMAT)
    else
      ActiveSupport::NumberHelper.number_to_delimited(rounded)
    end
  end

  def decimal(value)
    value.is_a?(Money) ? value.to_d : BigDecimal(value.to_s)
  rescue ArgumentError
    value
  end

  # Display-only currency label, on money columns only (E16)
  def currency_prefix(column)
    symbol = config.currency_symbol
    symbol.present? && config.monetized?(base_key(column)) ? "#{symbol} " : ""
  end

  def money_format(column)
    symbol = config.currency_symbol
    symbol.present? && config.monetized?(base_key(column)) ? "\"#{symbol}\"#,##0.00" : "#,##0.00"
  end

  # "relation.column" without the "; col-type" suffix or a pivot's "__pivot__<value>"
  def base_key(column)
    key = column.respond_to?(:key) ? column.key : column.to_s
    key.to_s.split(";").first.to_s.strip.split("__pivot__").first
  end

  def yes_no(value)
    return "Yes" if TRUE_VALUES.include?(value)
    return "No" if FALSE_VALUES.include?(value)

    value.to_s
  end

  def to_date(value)
    value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
  rescue ArgumentError
    value
  end

  def to_time(value)
    value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
  rescue ArgumentError
    value
  end

  def localize(value)
    value.respond_to?(:strftime) ? I18n.l(value) : value.to_s
  end
end
