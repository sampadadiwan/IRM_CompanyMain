class AccountEntryReportsController < ApplicationController
  include FundsHelper

  # Turbo Frame id wrapping the detail pivot. Paging the pivot re-requests the report
  # action, and matching on this id lets us build ONLY the pivot for that request
  # instead of recomputing the KPIs, both charts and the filter dropdowns as well.
  DETAIL_FRAME_ID = "account_entry_report_detail".freeze

  after_action :verify_authorized

  # account_entries is very large; the report scopes carry a MAX_EXECUTION_TIME hint
  # (AccountEntryReport::STATEMENT_TIMEOUT_MS) so a runaway range is killed by MySQL
  # rather than pinning a replica connection. Turn that into an actionable message
  # instead of a 500. See docs/modules/reports/account_entry_report_performance.md.
  rescue_from ActiveRecord::StatementInvalid, with: :handle_report_timeout

  # GET /account_entry_reports/fund_report
  def fund_report
    # The commitment dropdown is multi-select: 0 selected stays fund-level (optionally
    # narrowed to several folios below), exactly 1 means the user wants that investor's
    # own folio-level report, so hand off to that action.
    if commitment_ids_param.size == 1
      skip_authorization
      redirect_to folio_report_account_entry_reports_path(capital_commitment_id: commitment_ids_param,
                                                            start_date: params[:start_date], end_date: params[:end_date],
                                                            entry_names: entry_names_param, entry_types: entry_types_param,
                                                            allocation_run_id: allocation_run_id_param) and return
    end

    @fund = policy_scope(Fund).find(params[:fund_id])
    authorize @fund, :period_report?

    page = build_page(fund: @fund)
    # A fund-level, unfiltered scan of account_entries is one of the most expensive things
    # this app can be asked to do (see docs/modules/reports/account_entry_report_performance.md),
    # so nothing is queried against it until the request is narrow enough. A folio, entry name
    # or entry type does that — and so does a single allocation_run_id, which covers one fund
    # over one period and is indexed. See AccountEntryReportPage#filter_selected?; with none of
    # them this only resolves dates and populates the filter dropdowns.
    @filter_selected = page.filter_selected?

    # The pivot is only built for a chosen slice, never for a whole run — see
    # AccountEntryReportPage#explicit_filters?.
    @show_detail = page.explicit_filters?
    if @show_detail
      @detail_pivot = page.detail_pivot(page: params[:page])
      # Pivot pagination: render the frame alone and skip the rest of the page's queries.
      return render(partial: "account_entry_reports/detail_pivot", locals: { pivot: @detail_pivot }) if detail_frame_request?
    end

    assign_page(page, load_report: @filter_selected)
    fund_bread_crumbs("Account Entries Report")
  end

  # GET /account_entry_reports/dependencies
  # What each of a run's entry-name totals is built from. Fetched by a lazy Turbo Frame when
  # the reviewer opens that tab, so a report opened for the charts never pays for it. Building
  # it runs the report's first aggregate pass over account_entries and folds the rows out of
  # it, then reads the fund's formulas to link each row to the rows it depends on — see
  # AllocationRunTieOut's performance contract.
  def dependencies
    @fund = policy_scope(Fund).find(params[:fund_id])
    authorize @fund, :period_report?
    @allocation_run = AllocationRun.find_by!(id: params[:allocation_run_id], fund_id: @fund.id)

    report = AccountEntryReport.new(fund: @fund, start_date: @allocation_run.start_date,
                                    end_date: @allocation_run.end_date, allocation_run_id: @allocation_run.id)
    @totals = AllocationRunTieOut.new(report: report, fund: @fund, allocation_run: @allocation_run)

    render partial: "account_entry_reports/dependencies",
           locals: { totals: @totals, fund: @fund, allocation_run: @allocation_run }
  end

  # GET /account_entry_reports/tie_out
  # The fund totals sheet for one allocation run, as its own panel. Fetched by a lazy Turbo
  # Frame when the reviewer opens that tab, so a report opened to look at the charts never pays
  # for it. Building it runs the report's first aggregate pass over account_entries and folds
  # the rows out of it — see AllocationRunTieOut's performance contract.
  def tie_out
    @fund = policy_scope(Fund).find(params[:fund_id])
    authorize @fund, :period_report?
    # Scoped to this fund: a URL can pair any fund_id with any allocation_run_id, and an
    # unscoped lookup would draw the sheet over another fund's period while labelling it this
    # fund's. Same lookup #dependencies and #assign_page use.
    @allocation_run = AllocationRun.find_by!(id: params[:allocation_run_id], fund_id: @fund.id)

    report = AccountEntryReport.new(fund: @fund, start_date: @allocation_run.start_date,
                                    end_date: @allocation_run.end_date, allocation_run_id: @allocation_run.id)
    @tie_out = AllocationRunTieOut.new(report: report, fund: @fund, allocation_run: @allocation_run,
                                       with_figures: true)

    render partial: "account_entry_reports/tie_out",
           locals: { tie_out: @tie_out, fund: @fund, allocation_run: @allocation_run }
  end

  # GET /account_entry_reports/tie_out_folios
  # The folios behind one row of the fund totals sheet, rendered into the row's Turbo Frame.
  # Runs only when a reviewer opens a row, so the sheet itself stays free of per-row queries.
  def tie_out_folios
    @fund = policy_scope(Fund).find(params[:fund_id])
    authorize @fund, :period_report?
    @allocation_run = AllocationRun.find_by!(id: params[:allocation_run_id], fund_id: @fund.id)
    @name = params[:name].to_s
    # No AccountEntryReport here: this needs one bounded query for one name, not the page's
    # two aggregate passes.
    @folios = AllocationRunTieOut.new(report: nil, fund: @fund, allocation_run: @allocation_run).folios(@name)

    render partial: "account_entry_reports/tie_out_folios",
           locals: { folios: @folios, name: @name, fund: @fund, allocation_run: @allocation_run }
  end

  # GET /account_entry_reports/folio_report
  def folio_report
    # The commitment dropdown is multi-select: 0 selected means the user wants the
    # fund-level report, 2+ means they want a fund-level report filtered to those
    # folios - either way, hand off to the fund_report action instead.
    if commitment_ids_param.size != 1
      skip_authorization
      redirect_to fund_report_account_entry_reports_path(fund_id: params[:fund_id], capital_commitment_id: commitment_ids_param,
                                                           start_date: params[:start_date], end_date: params[:end_date],
                                                           entry_names: entry_names_param, entry_types: entry_types_param,
                                                           allocation_run_id: allocation_run_id_param) and return
    end

    @capital_commitment = policy_scope(CapitalCommitment).find(commitment_ids_param.first)
    authorize @capital_commitment, :period_report?
    @fund = @capital_commitment.fund

    # Already scoped to a single folio (that's what got the request routed here in the
    # first place), so it's cheap regardless of entry_names/entry_types — no need for the
    # fund-level gate above.
    page = build_page(fund: @fund, capital_commitment: @capital_commitment)
    assign_page(page, load_report: true)
    @entries = page.entries

    @bread_crumbs = { Funds: funds_path,
                      "#{@fund.name}": fund_path(@fund),
                      "#{@capital_commitment}": capital_commitment_path(@capital_commitment) }
    @bread_crumbs["Account Entries Report"] = nil
  end

  # POST /account_entry_reports/generate_commentary
  def generate_commentary
    @fund = policy_scope(Fund).find(params[:fund_id])
    @capital_commitment = policy_scope(CapitalCommitment).find(params[:capital_commitment_id]) if params[:capital_commitment_id].present?

    authorize(@capital_commitment || @fund, :period_report?)

    section_key = params[:section_key]
    start_date = params[:start_date]
    end_date = params[:end_date]
    redirect_path = @capital_commitment ? folio_report_account_entry_reports_path(capital_commitment_id: @capital_commitment.id, start_date: start_date, end_date: end_date) : fund_report_account_entry_reports_path(fund_id: @fund.id, start_date: start_date, end_date: end_date)

    # insight.save! below would otherwise raise ActiveRecord::RecordInvalid/StatementInvalid
    # (uncaught, 500) for a tampered or missing param instead of a clean redirect.
    valid_section = AccountEntryReportInsight::SECTION_KEYS.include?(section_key)
    redirect_to redirect_path, alert: "Invalid section or date range." and return unless valid_section && start_date.present? && end_date.present?

    mark_pending_and_enqueue(section_key, start_date, end_date)

    redirect_to redirect_path, notice: "AI commentary is being generated. Refresh in a moment to see it."
  end

  private

  # True only for the pivot's own pagination requests, so a normal full-page load (or a
  # Turbo Frame request for some other frame) still renders everything.
  def detail_frame_request?
    turbo_frame_request_id == DETAIL_FRAME_ID
  end

  # The report failed at the database. Send the user somewhere cheap rather than looping
  # on the range that just timed out. Re-raise anything that is not a timeout so real bugs
  # still surface, and re-raise once rendering has started - at that point a redirect is
  # impossible and swallowing the error would only turn it into a DoubleRenderError.
  # assign_page calls AccountEntryReport#preload! precisely so this stays reachable.
  def handle_report_timeout(exception)
    raise exception unless exception.message.match?(/max_execution_time|maximum execution time|query execution was interrupted/i)
    raise exception if response_body.present?

    Rails.logger.warn("[AccountEntryReport] statement timeout for #{request.fullpath}: #{exception.message}")
    # Deliberately NOT redirect_back: the referer is often the very URL that just timed
    # out, which would loop. Send the user somewhere known-cheap instead.
    redirect_to(@fund ? fund_path(@fund) : funds_path,
                alert: "That date range was too large to report on and the query was stopped. " \
                       "Please narrow the dates, or filter to specific folios or entry names, and try again.")
  end

  def build_page(fund:, capital_commitment: nil)
    AccountEntryReportPage.new(
      fund: fund, capital_commitment: capital_commitment,
      start_date_param: params[:start_date], end_date_param: params[:end_date],
      entry_names: entry_names_param, entry_types: entry_types_param, commitment_ids: commitment_ids_param,
      allocation_run_id: allocation_run_id_param
    )
  end

  # load_report is false only for the fund-level, no-filter-yet state: the filter form
  # (dates, dropdowns) still needs start_date/end_date/available options/commitment_ids to
  # render, but @report itself is left unpreloaded so nothing hits account_entries.
  def assign_page(page, load_report:)
    @start_date = page.start_date
    @end_date = page.end_date
    @entry_names = page.entry_names
    @entry_types = page.entry_types
    @commitment_ids = page.commitment_ids
    @allocation_run_id = page.allocation_run_id
    @available_entry_names = page.available_entry_names
    @available_entry_types = page.available_entry_types
    @commitment_options = page.commitment_options
    @report = page.report
    if load_report
      # Force every account_entries query now, while a statement timeout can still become
      # a redirect. Left lazy, these run inside the view partials, and rescue_from firing
      # mid-render yields a DoubleRenderError rather than the intended message.
      @report.preload!
      @insights = page.insights
    end
    # The run this report is scoped to, if any. Its totals sheet is a tab of its own and is
    # fetched lazily (see #tie_out), so nothing is folded for it here.
    #
    # Scoped to this fund on purpose: a URL can pair any fund_id with any allocation_run_id,
    # and a run belonging to a different fund would otherwise draw a tie-out sheet of the wrong
    # fund's totals. When the id does not resolve the tab still renders and says so — silently
    # dropping the tab looks exactly like the feature not existing.
    @allocation_run = AllocationRun.find_by(id: page.allocation_run_id, fund_id: @fund.id) if page.allocation_run_id
    # Surfaced by the views so a clamped range is visible, not silent.
    @range_clamped = page.range_clamped
    @requested_start_date = page.requested_start_date
  end

  def entry_names_param
    Array(params[:entry_names]).reject(&:blank?)
  end

  def entry_types_param
    Array(params[:entry_types]).reject(&:blank?)
  end

  def allocation_run_id_param
    params[:allocation_run_id].presence
  end

  def commitment_ids_param
    Array(params[:capital_commitment_id]).reject(&:blank?)
  end

  def mark_pending_and_enqueue(section_key, start_date, end_date)
    insight = ActiveRecord::Base.connected_to(role: :writing) do
      insight = AccountEntryReportInsight.find_or_initialize_by(
        fund_id: @fund.id, capital_commitment_id: @capital_commitment&.id,
        start_date: start_date, end_date: end_date, section_key: section_key
      )
      insight.entity_id ||= @fund.entity_id
      insight.status = "pending"
      insight.save!
      insight
    end

    AccountEntryReportCommentaryJob.perform_later(
      @fund.id, section_key, start_date.to_s, end_date.to_s,
      capital_commitment_id: @capital_commitment&.id, user_id: current_user.id
    )

    insight
  end
end
