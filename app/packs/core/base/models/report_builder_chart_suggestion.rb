# A chart for a Report Builder report, picked by rules from its columns — no AI
# call. The first rule that fits wins:
#
#   a pivot                       → stacked bars, one per pivot column, by the first text column
#   a date column + an amount     → a line of the first amount over the date
#   a text column + an amount     → a horizontal bar of the first amount, top 15 rows
#   anything else                 → nil ("No chart suggested")
#
# Built from the rows it is given (the preview's, or the report page's), so a
# saved suggested chart follows the report's data.
#
#   ReportBuilderChartSuggestion.for(config:, columns:, rows:) → { title:, spec: Chart.js config } | nil
#
# Worked examples H5, H7, E11, E12 — openspec/changes/report-builder-assistant/business-rules.md
class ReportBuilderChartSuggestion
  TOP = 15
  AMOUNT_TYPES = %i[money number integer].freeze
  DATE_TYPES = %i[date datetime].freeze

  def self.for(config:, columns:, rows:)
    new(config, columns, rows).suggestion
  end

  def initialize(config, columns, rows)
    @config  = config
    @columns = columns
    @rows    = rows
  end

  def suggestion
    # Pivot columns are dynamic columns of a report with a pivot; formula columns are dynamic too
    pivoted = @config.joins.any? { |j| j[:pivot].present? }
    pivots = pivoted ? @columns.grep(ReportBuilderDynamicColumn).reject { |c| c.key.to_s.start_with?("formula") } : []
    text   = first_of(%i[text])
    date   = first_of(DATE_TYPES)
    amount = first_of(AMOUNT_TYPES)

    if pivots.any? && text then stacked(text, pivots)
    elsif date && amount then line(date, amount)
    elsif text && amount then bar(text, amount)
    end
  end

  private

  def label(col)
    col.respond_to?(:label) && col.label.present? ? col.label : col.name
  end

  # The first stored column of these types, in report order (formulas and pivots skipped)
  def first_of(types)
    @columns.find do |col|
      next false if col.is_a?(ReportBuilderDynamicColumn) || col.key.to_s.start_with?("formula")

      types.include?(@config.column_type.base_type(col.key.to_s.split(";").first.strip))
    end
  end

  # A row's value for a column, whose key may carry a ";" display hint
  def value(row, col)
    row[col.key].nil? ? row[col.key.to_s.split(";").first.strip] : row[col.key]
  end

  def number(value)
    case value
    when Money then value.to_d.to_f
    when Numeric, String then value.to_f
    else 0.0
    end
  end

  def bar(text, amount)
    top = @rows.sort_by { |r| -number(value(r, amount)) }.first(TOP)
    { title: "Bar — #{label(amount)} by #{label(text)}",
      spec: chart("bar", top.map { |r| value(r, text).to_s }, [dataset(label(amount), top.map { |r| number(value(r, amount)) })],
                  "indexAxis" => "y") }
  end

  def line(date, amount)
    ordered = @rows.reject { |r| value(r, date).nil? }.sort_by { |r| value(r, date).to_s }
    { title: "Line — #{label(amount)} over #{label(date)}",
      spec: chart("line", ordered.map { |r| value(r, date).to_s }, [dataset(label(amount), ordered.map { |r| number(value(r, amount)) })]) }
  end

  def stacked(text, pivots)
    datasets = pivots.map { |p| dataset(label(p), @rows.map { |r| number(value(r, p)) }) }
    { title: "Stacked bar — #{pivots.map { |p| label(p) }.first(3).join(', ')}#{', …' if pivots.size > 3} by #{label(text)}",
      spec: chart("bar", @rows.map { |r| value(r, text).to_s }, datasets,
                  "scales" => { "x" => { "stacked" => true }, "y" => { "stacked" => true } }) }
  end

  def dataset(name, data)
    { "label" => name, "data" => data, "borderWidth" => 1 }
  end

  def chart(type, labels, datasets, options = {})
    { "type" => type, "data" => { "labels" => labels, "datasets" => datasets },
      "options" => { "responsive" => true, "maintainAspectRatio" => false }.merge(options) }
  end
end
