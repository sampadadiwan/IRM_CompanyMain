# Builds everything an Account Entries Period Report page needs - resolved date range,
# filter state, the AccountEntryReport itself, and cached AI insights - for either the
# fund-level report (capital_commitment nil) or a single folio's report.
#
# See docs/modules/reports/account_entry_report_performance.md. account_entries is very large,
# so this class is responsible for keeping the request bounded: it clamps the requested
# date range and it scopes every dropdown query to that range.
class AccountEntryReportPage
  # Hard ceiling on the requested reporting-date window. Without it a hand-edited URL
  # (start_date=2000-01-01&end_date=2030-12-31) scans every yearly partition of
  # account_entries. When the request exceeds this we move start_date forward and tell
  # the user we did, rather than silently returning a report for a different range.
  MAX_RANGE_DAYS = 731 # ~24 months

  attr_reader :start_date, :end_date, :entry_names, :entry_types, :commitment_ids,
              :allocation_run_id, :report, :requested_start_date, :range_clamped

  def initialize(fund:, start_date_param:, end_date_param:, entry_names:, entry_types:, commitment_ids:, capital_commitment: nil, allocation_run_id: nil)
    @fund = fund
    @capital_commitment = capital_commitment
    @entry_names = entry_names
    @entry_types = entry_types
    @commitment_ids = commitment_ids
    @allocation_run_id = allocation_run_id.presence

    set_date_range(start_date_param, end_date_param)
    # available_entry_names, available_entry_types and insights are deliberately NOT built
    # here. A Turbo Frame request that only re-renders the detail pivot (pagination)
    # constructs this object and calls detail_pivot alone, and must not pay for the filter
    # dropdown queries or the insight lookups it will never render.
    @report = AccountEntryReport.new(
      fund: fund, capital_commitment: capital_commitment, start_date: @start_date, end_date: @end_date,
      capital_commitment_ids: capital_commitment ? nil : @commitment_ids, entry_names: @entry_names,
      entry_types: @entry_types, allocation_run_id: @allocation_run_id
    )
  end

  # Entry names for the filter dropdown, scoped to the visible range. Lazy - see the
  # constructor. Without the range filter this plucked distinct names across the fund's
  # entire ledger history, which on a large entity is one of the most expensive queries
  # on the page. Names the user already has selected are unioned back in so an
  # out-of-range selection never silently disappears from the dropdown (and therefore
  # from the submitted filter).
  def available_entry_names
    @available_entry_names ||= begin
      # Carries the same MAX_EXECUTION_TIME ceiling as the report scopes: this is still
      # a DISTINCT over account_entries and must not outlive the request either.
      in_range = @report.with_statement_timeout(
        scope_for_available_filters.not_cumulative
                                   .where(reporting_date: @start_date..@end_date)
      ).distinct.pluck(:name)
      (in_range | Array(@entry_names)).compact.sort
    end
  end

  # Same as available_entry_names, but for the entry_type column. entry_type is a coarser
  # grouping than name (e.g. several formula names can share one type), and is indexed
  # with fund_id and reporting_date (idx_fund_id_and_entry_type_and_reporting_date), so
  # filtering by it is the cheaper of the two for a wide-ledger fund.
  def available_entry_types
    @available_entry_types ||= begin
      in_range = @report.with_statement_timeout(
        scope_for_available_filters.not_cumulative
                                   .where(reporting_date: @start_date..@end_date)
      ).distinct.pluck(:entry_type)
      (in_range | Array(@entry_types)).compact.sort
    end
  end

  # True once the request is narrow enough to run the report.
  #
  # Either the user picked at least one folio, entry name or entry type, or the request is
  # scoped to a single allocation run. account_entries is large enough that a fund-wide,
  # unfiltered scan is expensive (see docs/modules/reports/account_entry_report_performance.md)
  # — the controller uses this to decide whether to actually run the report or just show the
  # filter form.
  #
  # An allocation_run_id is a bound in its own right, not an excuse for the absence of one: a
  # run covers one fund over one period, allocation_run_id is indexed on account_entries
  # (index_account_entries_on_allocation_run_id), and the run's own dates clamp the reporting
  # date range on top of it. It was previously excluded here, which meant the "View Report"
  # link on the allocation screen — the one a reviewer follows to look at what a run produced —
  # landed on a filter form and showed nothing until they guessed a filter. Reviewing a run is
  # exactly the case this report is opened for.
  def filter_selected?
    run_scoped? || @entry_names.present? || @entry_types.present? || @commitment_ids.present?
  end

  # Scoped to one allocation run, which is what the fund totals sheet is drawn for.
  def run_scoped? = @allocation_run_id.present?

  # The user actually picked a folio, entry name or entry type — as opposed to arriving here
  # scoped to a run and nothing else. The detail pivot is built only for these: a run covers
  # every name and every folio, which is a pivot nobody can read and a page nobody wants to
  # wait for. The totals sheet is the summary of a whole run; the pivot is for a chosen slice.
  def explicit_filters? = @entry_names.present? || @entry_types.present? || @commitment_ids.present?

  # Returns { section_key => AccountEntryReportInsight or nil }. Lazy - see the
  # constructor. Never generates: commentary only generates when the user clicks
  # Generate/Regenerate (the generate_commentary controller action), so loading the
  # report is always cheap and never fires an LLM call.
  def insights
    @insights ||= AccountEntryReportInsight::SECTION_KEYS.index_with { |section_key| find_insight(section_key) }
  end

  def entries
    @entries ||= @report.scoped_entries.order(reporting_date: :asc)
  end

  # The pivot is handed the row list and the column headers the report has already
  # aggregated, so building it costs one indexed query for the visible page of folios
  # instead of that query plus two more DISTINCT scans of account_entries.
  def detail_pivot(page:)
    AccountEntryPivot.new(
      @report.scoped_entries,
      group_by: :name,
      show_breakdown: false,
      page: page,
      precomputed_rows: @report.folio_rows,
      precomputed_group_dates: @report.name_date_pairs
    ).call
  end

  # Options for the Investor/Folio multi-select. Built with a join + pluck because
  # `fund.capital_commitments.map(&:to_s)` instantiated every commitment AND fired one
  # investor_kyc query per row (an N+1 on a fund with thousands of folios). The label
  # here must stay in sync with CapitalCommitment#to_s: that's exactly what
  # account_entries.commitment_name is a snapshot of at the moment an entry is generated
  # (see AccountEntry::CreateAccountEntry), so under normal conditions this dropdown's
  # label and the detail pivot's Folio column read identically. They can still drift for
  # older entries if the investor's name or KYC changed since - that's a real change in
  # the investor's identity over time, not a bug, and the same reason the "folio touched"
  # KPI counts by capital_commitment_id rather than by this label (see
  # AccountEntryReport#summary_kpis).
  def commitment_options
    @commitment_options ||= @fund.capital_commitments
                                 .left_joins(:investor_kyc)
                                 .pluck(:id, :folio_id, :investor_name, "investor_kycs.full_name")
                                 .map do |id, folio_id, investor_name, kyc_full_name|
      label = if kyc_full_name.present?
                "#{kyc_full_name} - #{folio_id}"
              else
                "#{investor_name}, Folio: #{folio_id}"
              end
      [label, id]
    end
  end

  private

  def scope_for_available_filters
    scope = (@capital_commitment || @fund).account_entries
    scope = scope.where(allocation_run_id: @allocation_run_id) if @allocation_run_id
    scope
  end

  # not_cumulative here so the default date always matches what AccountEntryReport
  # will actually display - otherwise a fund whose latest reporting_date holds only
  # cumulative checkpoint entries would default to a date that renders an empty report.
  def set_date_range(start_date_param, end_date_param)
    entries_scope = (@capital_commitment || @fund).account_entries
    @end_date = end_date_param.presence&.to_date || entries_scope.not_cumulative.maximum(:reporting_date)
    # Fall back to today when the scope has no entries at all, so the rest of the page
    # works with real dates instead of nil (nil..nil matches every row).
    @end_date ||= Time.zone.today
    @start_date = start_date_param.presence&.to_date || @end_date
    clamp_range
  end

  def clamp_range
    @requested_start_date = @start_date
    @range_clamped = false
    # Guard the inverted-range case too: it would otherwise produce an empty report with
    # no explanation of why.
    @start_date = @end_date if @start_date > @end_date

    return if (@end_date - @start_date).to_i <= MAX_RANGE_DAYS

    @start_date = @end_date - MAX_RANGE_DAYS
    @range_clamped = true
  end

  def find_insight(section_key)
    AccountEntryReportInsight.find_by(
      fund_id: @fund.id, capital_commitment_id: @capital_commitment&.id,
      start_date: @start_date, end_date: @end_date, section_key: section_key
    )
  end
end
