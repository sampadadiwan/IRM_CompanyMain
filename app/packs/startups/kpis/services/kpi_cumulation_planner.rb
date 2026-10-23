require "bigdecimal"
require "date"

# Works out which Quarter, YTD and Year figures of one KPI series (one name, company and tag) should exist, from its
# approved month figures and its approved Quarter figures. Pure arithmetic: it reads nothing and writes nothing, so
# the rules can be exercised without a database. KpiCumulative#reconcile_cumulative_kpis then makes the saved rows
# match the answer.
#
# The work is done one fiscal year at a time:
#   1. settle_quarters decides which quarters exist: an uploaded Quarter figure is kept; a quarter whose 3 months all
#      exist gets a calculated figure; any other quarter has none. A missing month is never treated as zero.
#   2. walk goes through the fiscal year in order and gives the YTD and Year figures.
#
# Worked examples: openspec/changes/kpi-ytd-mixed-granularity/design.md (H1 to H7, E1 to E11, E35, E36, E38, E39).
class KpiCumulationPlanner
  QUARTER = "Quarter".freeze
  YTD = "YTD".freeze
  YEAR = "Year".freeze
  PERIOD_RANK = { QUARTER => 0, YTD => 1, YEAR => 2 }.freeze

  # @param months [Array<Hash>] approved Month figures, [{ as_of: Date, value: Numeric }]
  # @param quarters [Array<Hash>] approved Quarter figures, [{ as_of: Date, value: Numeric, calculated: Boolean }].
  #   A calculated one is earlier output of this planner, so it is never read as input.
  # @param fy_start_month [Integer] 1-based month the fiscal year starts in (KpiDateUtils.resolve_fiscal_year_start_month)
  # @param mode [Symbol] :sum adds figures up (cumulate); :last takes the latest balance (forward fill)
  # @param today [Date] Actual figures dated after it are not planned
  # @param tag [String] the report tag; Budget and IC may be future-dated
  # @return [Array<Hash>] [{ period: "Quarter"|"YTD"|"Year", as_of: Date, value: BigDecimal }], oldest first
  def self.plan(months:, quarters:, fy_start_month:, mode:, today:, tag:)
    new(months: months, quarters: quarters, fy_start_month: fy_start_month, mode: mode, today: today, tag: tag).plan
  end

  def initialize(months:, quarters:, fy_start_month:, mode:, today:, tag:)
    raise ArgumentError, "mode must be :sum or :last" unless %i[sum last].include?(mode)

    @mode = mode
    @today = today
    @actual = tag.to_s.casecmp?("Actual")
    @fy_start_month = fy_start_month
    @months = index_months(months)
    @uploaded = index_uploaded_quarters(quarters)
  end

  def plan
    rows = fiscal_years.flat_map do |fy|
      settled = settle_quarters(fy)
      quarter_rows(fy, settled) + walk(fy, settled)
    end
    rows.select { |row| plannable?(row[:as_of]) }
        .sort_by { |row| [row[:as_of], PERIOD_RANK.fetch(row[:period])] }
  end

  # The quarters of one fiscal year that exist, keyed 1..4: { origin: :uploaded | :calculated, value:, as_of: }.
  # H2, E1, E5: an uploaded Quarter figure is kept even when all 3 months exist; otherwise a quarter whose 3 months
  # all exist is calculated; otherwise there is none.
  def settle_quarters(fy)
    (1..4).each_with_object({}) do |quarter, settled|
      uploaded = @uploaded.dig(fy, quarter)
      months = quarter_months(fy, quarter)
      if uploaded
        settled[quarter] = { origin: :uploaded, value: uploaded[:value], as_of: uploaded[:as_of] }
      elsif months.all?
        settled[quarter] = { origin: :calculated, value: quarter_value(months), as_of: quarter_end(fy, quarter) }
      end
    end
  end

  # The YTD and Year rows of one fiscal year, walking its quarters in order.
  #
  # :sum (cumulate). `base` is the total of the quarters before this one and is not touched while the months of
  # the current quarter are walked, so a quarter bridged by a Quarter figure never counts its partial months twice
  # (E3). Months count while they are contiguous from the start of the quarter (E2). At the end of the quarter the
  # total is base plus the 3 months when all exist (they win over an uploaded Quarter, E4), else base plus the
  # uploaded Quarter figure (H1, H3, E38), else the fiscal year stops there. The Year is the total after Q4 (H4, H5).
  #
  # :last (forward fill). A balance is a snapshot, so the YTD at a date is the balance at that date and there is no
  # gap to stop at (E36): each month with a figure gets its own balance (a month wins over a Quarter figure on the same
  # date). A quarter end that only an uploaded Quarter figure covers gets that figure as its balance, never added to an
  # earlier quarter (H6, E39). The Year is the Q4 balance, and only when all 4 quarters are covered.
  def walk(fy, settled)
    @mode == :sum ? walk_sum(fy, settled) : walk_last(fy, settled)
  end

  private

  def walk_sum(fy, settled)
    rows = []
    base = BigDecimal("0")
    (1..4).each do |quarter|
      months = quarter_months(fy, quarter)
      running = base
      months.each do |month|
        break unless month

        running += month[:value]
        rows << { period: YTD, as_of: month[:as_of], value: running }
      end

      if months.all?
        base = running
      elsif settled[quarter]
        # Only an uploaded Quarter can be here (a calculated one needs its 3 months). It covers the quarter end even
        # when a month inside the quarter is missing and a month dated at the quarter end exists (E38).
        base += settled[quarter][:value]
        rows << { period: YTD, as_of: quarter_end(fy, quarter), value: base }
      else
        return rows
      end
    end
    rows << { period: YEAR, as_of: (fy >> 12) - 1, value: base }
  end

  def walk_last(fy, settled)
    rows = []
    (1..4).each do |quarter|
      months = quarter_months(fy, quarter)
      months.each do |month|
        rows << { period: YTD, as_of: month[:as_of], value: month[:value] } if month
      end
      # Only an uploaded Quarter can cover a quarter end that has no month figure (a calculated one needs its 3 months)
      rows << { period: YTD, as_of: quarter_end(fy, quarter), value: settled[quarter][:value] } if months.last.nil? && settled[quarter]
    end

    if (1..4).all? { |quarter| settled[quarter] }
      q4_end_month = quarter_months(fy, 4).last
      rows << { period: YEAR, as_of: (fy >> 12) - 1, value: q4_end_month ? q4_end_month[:value] : settled[4][:value] }
    end
    rows
  end

  # Calculated Quarter rows only: an uploaded Quarter row already exists and is never written by cumulation
  def quarter_rows(fy, settled)
    settled.filter_map do |quarter, entry|
      next unless entry[:origin] == :calculated

      { period: QUARTER, as_of: quarter_end(fy, quarter), value: entry[:value] }
    end
  end

  # :sum adds the 3 months; :last is the balance at the end of the quarter
  def quarter_value(months)
    @mode == :sum ? months.sum(BigDecimal("0")) { |month| month[:value] } : months.last[:value]
  end

  # Actual figures dated after today are not planned; Budget and IC may be future-dated (H7, E9)
  def plannable?(as_of)
    !(@actual && as_of > @today)
  end

  # Fiscal years (by their first day) holding any month figure or uploaded Quarter figure
  def fiscal_years
    (@months.keys + @uploaded.keys).uniq.sort
  end

  # The 3 month figures of a fiscal quarter, in order; nil where a month has no figure
  def quarter_months(fy, quarter)
    (0..2).map do |offset|
      slot = fy >> ((3 * (quarter - 1)) + offset)
      @months.dig(fy, [slot.year, slot.month])
    end
  end

  # Last day of a fiscal quarter
  def quarter_end(fy, quarter)
    (fy >> (3 * quarter)) - 1
  end

  def index_months(months)
    months.each_with_object({}) do |month, index|
      as_of = month.fetch(:as_of)
      fy = fiscal_year_start(as_of)
      (index[fy] ||= {})[[as_of.year, as_of.month]] = { as_of: as_of, value: decimal(month.fetch(:value)) }
    end
  end

  def index_uploaded_quarters(quarters)
    quarters.each_with_object({}) do |quarter, index|
      next if quarter[:calculated]

      as_of = quarter.fetch(:as_of)
      fy = fiscal_year_start(as_of)
      (index[fy] ||= {})[KpiDateUtils.fiscal_quarter(as_of, @fy_start_month)] = { as_of: as_of, value: decimal(quarter.fetch(:value)) }
    end
  end

  def fiscal_year_start(date)
    KpiDateUtils.fiscal_year_start(date, @fy_start_month)
  end

  def decimal(value)
    value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
  end
end
