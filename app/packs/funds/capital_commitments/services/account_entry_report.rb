# Aggregation layer for the Account Entries Period Report (fund-level when
# capital_commitment is nil, folio-level when present). Returns raw cents/counts
# only - currency formatting and chart rendering stay in the views/helpers.
class AccountEntryReport
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
    entries
  end

  def summary_kpis
    entries = scoped_entries

    {
      total_amount_cents: entries.sum(:amount_cents),
      entry_count: entries.count,
      distinct_folio_count: @capital_commitment ? 1 : entries.where.not(capital_commitment_id: nil).distinct.count(:capital_commitment_id),
      distinct_entry_names: entries.distinct.count(:name)
    }
  end

  # Memoized: the report views call this directly for the breakdown chart, and
  # trailing_trend calls it again internally to pick top names - without caching,
  # every render would run the grouped-sum query against account_entries twice.
  def breakdown_by_name
    @breakdown_by_name ||= scoped_entries.group(:name).sum(:amount_cents)
  end

  # Trailing-period series for the `top_names` entry names by absolute amount in
  # the current range, ending at end_date. Returns { name => { period_date => amount_cents } }.
  def trailing_trend(periods: 4, aggregate_by: 'quarter', top_names: 5)
    names = breakdown_by_name.sort_by { |_, amount| -amount.abs }.first(top_names).map(&:first)
    return {} if names.empty?

    # Bound the lower end of the range (with buffer for periods that don't land
    # exactly on a boundary) so MySQL can prune partitions instead of scanning
    # the fund's entire account_entries history for a handful of trend periods.
    lookback_start = @end_date - lookback_duration(aggregate_by, periods)
    base = @fund.account_entries.not_cumulative.where(name: names, reporting_date: lookback_start..@end_date)
    base = base.where(capital_commitment_id: @capital_commitment.id) if @capital_commitment

    group_field = AccountEntryPeriodGrouping.group_field_sql(aggregate_by)
    raw_data = base.group(Arel.sql(group_field), :name).sum(:amount_cents)

    all_periods = raw_data.keys.map(&:first).uniq.sort.last(periods)

    names.index_with do |name|
      all_periods.index_with { |period| raw_data[[period, name]] || 0 }
    end
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
