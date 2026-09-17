class ReportBuilderTable < ViewComponent::Base
  def initialize(report:, columns:, rows:, q:, turbo_frame: "report_builder_view")
    super()
    @report = report
    @columns = columns
    @rows = rows
    @q = q
    @turbo_frame = turbo_frame
    # Needed for currency_prefix below — nil currency (today's default for
    # every existing report) means currency_symbol is nil and prefixing is a no-op.
    @config = ReportBuilderConfig.new(report.template)
  end

  private

  def column_label(col)
    col.respond_to?(:label) ? col.label : col[:label]
  end

  def column_key(col)
    col.respond_to?(:key) ? col.key : col[:key]
  end

  def format_value(val, key)
    if val.is_a?(Date) || val.is_a?(Time) || val.is_a?(DateTime)
      l(val)
    # "__pivot__" marks a dynamic pivot column (see ReportBuilderPivotAggregator) —
    # numeric like "amount"/"num-col" columns, but not caught by those substrings.
    # Kept in sync with numeric_col? in ReportBuilderXlsxExporter.
    elsif val.is_a?(Numeric) && (key.include?("num-col") || key.include?("amount") || key.include?("formula") || key.include?("__pivot__"))
      "#{currency_prefix(key)}#{number_with_precision(val, precision: 2, delimiter: ',')}"
    else
      val
    end
  end

  # Prefixes monetized columns with the report's configured currency symbol
  # (e.g. "$ 1,234.00"). Purely a display label — no conversion happens here.
  # Returns "" whenever no currency is configured or the column isn't monetized,
  # so unconfigured reports render byte-for-byte as they did before this existed.
  def currency_prefix(key)
    symbol = @config.currency_symbol
    return "" unless symbol.present? && @config.monetized?(base_key_for(key))

    "#{symbol} "
  end

  # Strips the "; col-type" suffix and, for a pivot column, the "__pivot__<value>"
  # suffix, leaving the plain "relation.column" (or "column") path monetized? expects.
  def base_key_for(key)
    key.to_s.split(";").first.strip.split("__pivot__").first
  end
end
