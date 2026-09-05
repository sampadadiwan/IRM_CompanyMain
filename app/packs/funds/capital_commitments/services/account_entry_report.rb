# Aggregation layer for the Account Entries Period Report (fund-level when
# capital_commitment is nil, folio-level when present). Returns raw cents/counts
# only - currency formatting and chart rendering stay in the views/helpers.
#
# PERFORMANCE CONTRACT (see docs/technical/account_entry_report_performance.md):
# account_entries is a very large partitioned table, so this class issues exactly
# TWO aggregate passes over it for the whole page - one grouped by (name,
# reporting_date) and one grouped by capital_commitment_id - and derives every KPI,
# the breakdown chart and the pivot's row/column headers from those in Ruby. Do not
# add a `scoped_entries.count`/`.sum`/`.distinct` call here: each one is another full
# range scan. Add a reader off the existing aggregates instead.
class AccountEntryReport
  # Ceiling for a single report query on MySQL, enforced with a MAX_EXECUTION_TIME
  # optimizer hint so a runaway range fails fast instead of pinning a replica
  # connection and a Puma worker for minutes. Raises ActiveRecord::StatementInvalid,
  # which the controller turns into a "narrow your range" message.
  STATEMENT_TIMEOUT_MS = 15_000

  # capital_commitment scopes the report to a single folio (folio-level report).
  # capital_commitment_ids instead filters a fund-level report down to a chosen set of
  # folios, without narrowing the report to any one investor's identity.
  def initialize(fund:, start_date:, end_date:, capital_commitment: nil, capital_commitment_ids: nil, entry_names: nil)
    @fund = fund
    @capital_commitment = capital_commitment
    @capital_commitment_ids = capital_commitment_ids.presence
    @start_date = start_date
    @end_date = end_date
    @entry_names = entry_names.presence
  end

  def scoped_entries
    entries = @fund.account_entries.not_cumulative.where(reporting_date: @start_date..@end_date)
    entries = entries.where(capital_commitment_id: @capital_commitment.id) if @capital_commitment
    entries = entries.where(capital_commitment_id: @capital_commitment_ids) if @capital_commitment_ids
    entries = entries.where(name: @entry_names) if @entry_names
    with_statement_timeout(entries)
  end

  # PASS 1 of 2. [[name, reporting_date, sum_amount_cents, entry_count], ...]
  # Feeds summary_kpis, breakdown_by_name and the pivot's column headers.
  def name_date_totals
    @name_date_totals ||= scoped_entries
                          .group(:name, :reporting_date)
                          .pluck(:name, :reporting_date, Arel.sql("SUM(amount_cents)"), Arel.sql("COUNT(*)"))
  end

  # PASS 2 of 2. [[commitment_name, capital_commitment_id], ...] for every folio with
  # entries in range, ordered by name so the pivot's pagination is stable across loads.
  # Fund-level entries (capital_commitment_id NULL) are collapsed into one row, matching
  # what AccountEntryPivot produced when it ran this DISTINCT itself.
  def folio_rows
    @folio_rows ||= scoped_entries
                    .group(:commitment_name, :capital_commitment_id)
                    .pluck(:commitment_name, :capital_commitment_id)
                    .sort_by { |name, id| [name.to_s, id.to_i] }
  end

  def summary_kpis
    {
      # Derived from pass 1 - no extra queries.
      total_amount_cents: name_date_totals.sum { |_name, _date, amount, _count| amount.to_d },
      entry_count: name_date_totals.sum { |_name, _date, _amount, count| count.to_i },
      distinct_entry_names: name_date_totals.map(&:first).uniq.size,
      # Derived from pass 2. Count distinct IDS, not rows: folio_rows is grouped by
      # (commitment_name, capital_commitment_id), and commitment_name is denormalized onto
      # account_entries, so one folio whose investor was renamed mid-period contributes
      # several rows for a single id. A NULL id is a fund-level entry, not a folio.
      distinct_folio_count: @capital_commitment ? 1 : folio_rows.filter_map(&:last).uniq.size
    }
  end

  # Breakdown chart data, folded out of pass 1 rather than re-grouping in SQL.
  def breakdown_by_name
    @breakdown_by_name ||= name_date_totals.each_with_object(Hash.new(0)) do |(name, _date, amount, _count), acc|
      acc[name] += amount.to_d
    end
  end

  # Pivot column headers, folded out of pass 1. Returns [[name, reporting_date], ...]
  # in the same shape AccountEntryPivot would have plucked for itself.
  def name_date_pairs
    @name_date_pairs ||= name_date_totals.map { |name, date, _amount, _count| [name, date] }
  end

  # Forces every account_entries query this report will make, so they all happen inside
  # the controller action rather than lazily inside a view. That is what lets the
  # controller's statement-timeout rescue redirect: an exception raised mid-render can
  # only ever become a DoubleRenderError. Call before rendering.
  def preload!
    summary_kpis
    breakdown_by_name
    trailing_trend
    self
  end

  # Trailing-period series for the `top_names` entry names by absolute amount in
  # the current range, ending at end_date. Returns { name => { period_date => amount_cents } }.
  # Memoised per argument set: the view calls this with the defaults and preload! calls it
  # first, and it must not run the grouped query twice for one page.
  def trailing_trend(periods: 4, aggregate_by: 'quarter', top_names: 5)
    @trailing_trend ||= {}
    key = [periods, aggregate_by, top_names]
    return @trailing_trend[key] if @trailing_trend.key?(key)

    @trailing_trend[key] = compute_trailing_trend(periods, aggregate_by, top_names)
  end

  def compute_trailing_trend(periods, aggregate_by, top_names)
    names = breakdown_by_name.sort_by { |_, amount| -amount.abs }.first(top_names).map(&:first)
    return {} if names.empty?

    # Bound the lower end of the range (with buffer for periods that don't land
    # exactly on a boundary) so MySQL can prune partitions instead of scanning
    # the fund's entire account_entries history for a handful of trend periods.
    lookback_start = @end_date - lookback_duration(aggregate_by, periods)
    base = @fund.account_entries.not_cumulative.where(name: names, reporting_date: lookback_start..@end_date)
    base = base.where(capital_commitment_id: @capital_commitment.id) if @capital_commitment
    # Fund-level report filtered to a subset of folios: the trend has to honour that
    # subset too, otherwise the chart silently shows fund-wide numbers next to
    # folio-filtered KPIs. (`names` already carries the entry_names filter.)
    base = base.where(capital_commitment_id: @capital_commitment_ids) if @capital_commitment_ids
    base = with_statement_timeout(base)

    group_field = AccountEntryPeriodGrouping.group_field_sql(aggregate_by)
    raw_data = base.group(Arel.sql(group_field), :name).sum(:amount_cents)

    all_periods = raw_data.keys.map(&:first).uniq.sort.last(periods)

    names.index_with do |name|
      all_periods.index_with { |period| raw_data[[period, name]] || 0 }
    end
  end

  # Public so AccountEntryReportPage can put the same ceiling on the filter-dropdown
  # query, which hits account_entries too.
  # MAX_EXECUTION_TIME is MySQL-only syntax; the test environment runs SQLite, which
  # rejects the hint, so apply it per-adapter rather than unconditionally.
  def with_statement_timeout(relation)
    return relation unless relation.connection.adapter_name.match?(/mysql/i)

    relation.optimizer_hints("MAX_EXECUTION_TIME(#{STATEMENT_TIMEOUT_MS})")
  end

  private

  def lookback_duration(aggregate_by, periods)
    buffer = periods + 1
    case aggregate_by.to_s.downcase
    when 'year'
      buffer.years
    when 'month'
      buffer.months
    else # quarter
      (buffer * 3).months
    end
  end
end
