# Builds everything an Account Entries Period Report page needs - resolved date range,
# filter state, the AccountEntryReport itself, and cached AI insights - for either the
# fund-level report (capital_commitment nil) or a single folio's report.
class AccountEntryReportPage
  attr_reader :start_date, :end_date, :entry_names, :commitment_ids, :available_entry_names, :report, :insights

  def initialize(fund:, start_date_param:, end_date_param:, entry_names:, commitment_ids:, capital_commitment: nil)
    @fund = fund
    @capital_commitment = capital_commitment
    @entry_names = entry_names
    @commitment_ids = commitment_ids

    set_date_range(start_date_param, end_date_param)
    @available_entry_names = scope_for_available_names.not_cumulative.distinct.order(:name).pluck(:name)
    @report = AccountEntryReport.new(
      fund: fund, capital_commitment: capital_commitment, start_date: @start_date, end_date: @end_date,
      capital_commitment_ids: capital_commitment ? nil : @commitment_ids, entry_names: @entry_names
    )
    @insights = load_insights
  end

  def entries
    @entries ||= @report.scoped_entries.order(reporting_date: :asc)
  end

  def detail_pivot(page:)
    AccountEntryPivot.new(@report.scoped_entries, group_by: :name, show_breakdown: false, page: page).call
  end

  private

  def scope_for_available_names
    (@capital_commitment || @fund).account_entries
  end

  # not_cumulative here so the default date always matches what AccountEntryReport
  # will actually display - otherwise a fund whose latest reporting_date holds only
  # cumulative checkpoint entries would default to a date that renders an empty report.
  def set_date_range(start_date_param, end_date_param)
    entries_scope = (@capital_commitment || @fund).account_entries
    @end_date = end_date_param.presence&.to_date || entries_scope.not_cumulative.maximum(:reporting_date)
    @start_date = start_date_param.presence&.to_date || @end_date
  end

  # Returns { section_key => AccountEntryReportInsight or nil }. Never generates -
  # commentary only generates when the user clicks Generate/Regenerate (the
  # generate_commentary controller action), so loading the report is always cheap and
  # never fires an LLM call.
  def load_insights
    AccountEntryReportInsight::SECTION_KEYS.index_with { |section_key| find_insight(section_key) }
  end

  def find_insight(section_key)
    AccountEntryReportInsight.find_by(
      fund_id: @fund.id, capital_commitment_id: @capital_commitment&.id,
      start_date: @start_date, end_date: @end_date, section_key: section_key
    )
  end
end
