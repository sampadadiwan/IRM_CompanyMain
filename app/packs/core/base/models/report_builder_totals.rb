# The totals row for a set of Report Builder rows: sums every column the
# column-type resolver calls totalable (root numbers, Sum/Count totals, Sum/Count
# pivots), then recalculates formula columns from those totals — so Called %
# in the totals row is total called ÷ total committed, not a sum of percentages.
#
#   scope :all     every row of the report is here      → "Total"
#   scope :page    one page of a paged report page      → "Total (this page)"
#   scope :sample  the preview's first rows             → "Total (these N rows)"
#
# Worked examples H17, H18, E17, E18, E19, E30, E31 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderTotals
  def initialize(rows:, columns:, config:, scope: :all)
    @rows    = rows
    @columns = columns
    @config  = config
    @scope   = scope
  end

  # { column key => total } — nil when no column can be totalled (E19)
  def call
    return @call if defined?(@call)

    totalable = columns.select { |c| config.column_type.totalable?(c) }
    return @call = nil if totalable.empty?

    totals = totalable.to_h { |c| [c.key, sum(c.key)] }

    # Formulas recalculated from the totals (H18, E31); a formula that can't be
    # worked out from them (e.g. it uses a non-totalled column) stays blank
    formula_keys = config.formulas.map { |f| f[:key].to_s } & columns.map(&:key)
    if formula_keys.any?
      evaluated = ReportBuilderFormulaService.new(config.formulas.map(&:to_h)).evaluate(totals.dup)
      formula_keys.each { |k| totals[k] = evaluated[k] }
    end

    @call = totals
  end

  def label
    case scope
    when :page   then "Total (this page)"
    when :sample then "Total (these #{rows.size} rows)"
    else "Total"
    end
  end

  private

  attr_reader :rows, :columns, :config, :scope

  # Blank cells count as zero; anything that isn't a number is skipped (E30)
  def sum(key)
    rows.sum(BigDecimal("0")) do |row|
      value = row[key]
      case value
      when Money then value.to_d
      when Numeric then BigDecimal(value.to_s)
      when String then value.match?(/\A-?\d+(\.\d+)?\z/) ? BigDecimal(value) : 0
      else 0
      end
    end
  end
end
