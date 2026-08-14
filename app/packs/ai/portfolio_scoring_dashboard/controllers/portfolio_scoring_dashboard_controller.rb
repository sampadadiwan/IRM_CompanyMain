# frozen_string_literal: true

# Standalone dashboard for PortfolioScoringAgent output — buckets every
# portfolio company into a grade tier and makes each tier a drill-down.
#
# Mirrors PortfolioCompanyDashboardController's shape (stat cards, chart,
# filtered Turbo Frame table, footer) so the two agent dashboards behave
# identically for the FM.
#
# @see PortfolioScoringPresenter
# @see PortfolioScoringAgent
class PortfolioScoringDashboardController < ApplicationController
  # Included explicitly rather than relying on include_all_helpers, so the
  # dashboard's link helpers resolve regardless of that global setting.
  helper PortfolioScoringDashboardHelper

  # Score and delta live inside json_fields, so the page is sorted in Ruby and
  # paginated from an Array. The array extra is commented out in the global Pagy
  # initializer — required here rather than enabled app-wide, matching
  # DealsController.
  require 'pagy/extras/array'

  before_action :set_support_agent

  # How far back to load scoring reports. Bounds the query by companies ×
  # runs-per-year rather than by all history — json_fields carries the full
  # dimension payload per row, so an unbounded load is expensive.
  LOOK_BACK = 12.months

  # Table columns the FM can sort by. Score and delta live inside json_fields,
  # so they cannot be ordered in SQL — the page is sorted in Ruby and paginated
  # with pagy_array. The row set is already fully loaded for the presenter, so
  # this costs no extra query.
  SORTABLE_COLUMNS = %w[company sector score delta scored].freeze

  # Worst first. This dashboard exists for triage, so the companies needing
  # attention should be on the first page without the FM asking.
  DEFAULT_SORT = "score"
  DEFAULT_DIRECTION = "asc"

  # Columns the presenter actually reads. Everything else on the row is skipped
  # because json_fields is already wide (dimensions, rationales, positives,
  # concerns) and dominates per-row memory.
  #
  # Table-qualified: the table scope joins :investor, and `investors` carries
  # its own `id`, `json_fields` and `created_at` columns — unqualified names
  # raise "Column is ambiguous" on MySQL.
  REPORT_COLUMNS = %w[
    id owner_id owner_type owner_name support_agent_id status json_fields created_at updated_at
  ].map { |column| "support_agent_reports.#{column}" }.freeze

  # GET /portfolio_scoring_dashboard
  #
  # Loads every scoring report in the look-back window (not just the latest per
  # company — the movement figures need each company's previous run too), builds
  # the presenter, then narrows a separate scope for the paginated table.
  #
  # Two scopes are intentional and match the portco dashboard: the presenter
  # needs .includes(:owner), the table needs .joins(:investor) for Ransack.
  #
  # @return [void]
  def show
    @basis = params[:basis] == "value" ? :value : :count
    # An unrecognised slug used to fall through tier_meta to NOT_SCORED, so a
    # typo'd or stale bookmark rendered a "Not Scored" chip over an empty table.
    @status_filter = params[:status].presence
    @status_filter = nil unless PortfolioScoringPresenter.filter_slugs.include?(@status_filter)
    @sector_filter = params[:sector].presence
    @tag_filter = params[:tag].presence
    @search_value = params.dig(:q, :investor_investor_name_cont)

    # Sector and tag narrow the portfolio itself, so they are applied before the
    # presenter runs — the cards, chart, movement figures and percentages all
    # describe the filtered subset rather than the whole book. The tier filter
    # and the name search narrow only the table, which is why they are applied
    # further down.
    @scoped_company_ids = scoped_company_ids

    all_reports = scoring_reports_scope.includes(:owner).to_a
    @presenter = PortfolioScoringPresenter.new(all_reports, @support_agent,
                                               basis: @basis,
                                               company_ids: @scoped_company_ids)

    # Target selector data for the "Run scoring on" dropdown. Only companies with
    # a sector can be scored — a blank sector means no skill file can be matched,
    # so PortfolioScoringAgent#targets skips them entirely.
    scorable = portfolio_companies_scope.where.not(sector: [nil, ""])
    @portfolio_companies = scorable.order(:investor_name).pluck(:investor_name, :id)
    # A run is never limited to the page's sector/tag scope, so the modal quotes
    # portfolio-wide totals on both sides of "N of M companies qualify".
    @total_portfolio_companies = portfolio_companies_scope.count

    # Sector and tag lists are built from the whole portfolio, not the filtered
    # subset — otherwise selecting a sector would empty the dropdown that got
    # you there. Counts come from all portfolio companies so the FM can see how
    # big each slice is before switching to it.
    @sectors_for_select = portfolio_companies_scope.pluck(:sector).compact
                                                   .map(&:strip).compact_blank
                                                   .tally.sort_by { |sector, _| sector }
    @tags_for_select = portfolio_companies_scope.pluck(:tag_list).compact
                                                .flat_map { |t| t.split(",") }
                                                .map(&:strip).compact_blank
                                                .tally.sort_by { |tag, _| tag }

    # Table scope: one row per company (latest report only), Ransack-searchable.
    @sort = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
    @direction = params[:dir] == "desc" ? "desc" : DEFAULT_DIRECTION

    # includes(:owner) matters more than usual here: sort_rows calls
    # company_name/sector_for on EVERY filtered row (not just the page), so
    # without it, sorting by company issued one query per company in the filter.
    table_scope = scoring_reports_scope.joins(:investor).includes(:owner)
                                       .where(support_agent_reports: { id: @presenter.latest_report_ids })
    table_scope = filter_by_tier(table_scope, @presenter, @status_filter)
    @q = table_scope.ransack(params[:q])
    @pagy, @paginated_reports = pagy_array(sort_rows(@q.result.to_a), limit: 10)
  end

  # POST /portfolio_scoring_dashboard/run_scoring
  #
  # Enqueues a scoring run over the selected companies. Uses the shared
  # SupportAgentJob batch path (batch_ids + batch_ids_type) rather than a
  # dedicated job — PortfolioScoringAgent.process_batch needs no agent-specific
  # parameters, unlike PortfolioCompanyAgent's check_as_on_date.
  #
  # @return [void]
  # @see #resolve_target_ids
  def run_scoring
    authorize @support_agent, :run?

    target_ids = resolve_target_ids
    if target_ids.empty?
      redirect_to portfolio_scoring_dashboard_path,
                  alert: "No portfolio companies matched that selection. Companies need a sector set to be scored."
      return
    end

    SupportAgentJob.perform_later(
      support_agent_id: @support_agent.id,
      batch_ids: target_ids,
      batch_ids_type: "Investor",
      user_id: current_user.id,
      execution_mode: :adhoc_batch
    )

    redirect_to portfolio_scoring_dashboard_path,
                notice: "Scoring started for #{target_ids.size} #{'company'.pluralize(target_ids.size)}. Results appear here as each run finishes."
  end

  private

  # @return [void]
  def set_support_agent
    @support_agent = SupportAgent.find_by!(
      agent_type: "PortfolioScoringAgent",
      entity_id: current_user.entity_id
    )
    authorize @support_agent, :show?

    @bread_crumbs = {
      'Portfolio Scoring Dashboard': portfolio_scoring_dashboard_path
    }
  end

  # Every scoring report for this agent inside the look-back window.
  #
  # Reuses AgentReportsQuery#scoring_reports' predicate: rows carrying a "score"
  # (successful) or an "error" (failed), excluding the step-tracking rows the
  # agent also writes for the same (owner, support_agent) pair — those always
  # carry a "steps" key and scoring reports never do.
  #
  # Deliberately does NOT rely on the `latest` flag. mark_as_latest! scopes
  # `latest` per (owner, support_agent), and this agent writes both a step row
  # and a scoring row for that pair; the scoring row only wins today because it
  # is created last in store_score. Grouping per owner in the presenter is
  # needed for the movement figures anyway, so it does both jobs.
  #
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def scoring_reports_scope
    SupportAgentReport
      .where(support_agent: @support_agent, owner_type: "Investor")
      .where(support_agent_reports: { created_at: LOOK_BACK.ago.. })
      .where(
        "(support_agent_reports.json_fields LIKE '%\"score\":%' " \
        "OR support_agent_reports.json_fields LIKE '%\"error\":%') " \
        "AND support_agent_reports.json_fields NOT LIKE '%\"steps\":%'"
      )
      .select(*REPORT_COLUMNS)
      .order("support_agent_reports.created_at DESC")
      .then { |scope| @scoped_company_ids ? scope.where(owner_id: @scoped_company_ids) : scope }
  end

  # Investor ids matching the sector/tag filters, or nil when neither is set.
  # nil (rather than "every id") keeps the unfiltered query free of a needless
  # IN clause listing the whole portfolio.
  #
  # @return [Array<Integer>, nil]
  def scoped_company_ids
    return nil if @sector_filter.blank? && @tag_filter.blank?

    scope = portfolio_companies_scope
    scope = scope.in_sector([@sector_filter]) if @sector_filter.present?
    scope = scope.with_tag_list([@tag_filter]) if @tag_filter.present?
    scope.pluck(:id)
  end

  # Orders the page in Ruby, because score and delta are computed from
  # json_fields rather than stored in columns.
  #
  # Rows with no value for the active sort key (a failed run has no score, a
  # first-run company has no delta) always sort last, in both directions —
  # flipping the direction should not promote missing data to the top.
  #
  # @param reports [Array<SupportAgentReport>]
  # @return [Array<SupportAgentReport>]
  def sort_rows(reports)
    # Compute each key once; sort_by would otherwise re-derive it per comparison.
    keyed = reports.map { |report| [sort_key(report), report] }
    present_rows, missing_rows = keyed.partition { |key, _| !key.nil? }

    present_rows = present_rows.sort_by(&:first)
    present_rows = present_rows.reverse if @direction == "desc"

    (present_rows + missing_rows).map(&:last)
  end

  # @param report [SupportAgentReport]
  # @return [Comparable, nil] nil when this row has no value for the sort key
  def sort_key(report)
    case @sort
    when "company" then @presenter.company_name(report).to_s.downcase
    when "sector"  then @presenter.sector_for(report).to_s.downcase.presence
    when "delta"   then @presenter.delta_for(report)
    when "scored"  then report.created_at
    else @presenter.score_for(report)
    end
  end

  # @return [ActiveRecord::Relation<Investor>]
  def portfolio_companies_scope
    Investor.where(entity_id: current_user.entity_id)
            .where("LOWER(category) = ?", "portfolio company")
  end

  # Narrows the table to one grade tier. Tier is computed from json_fields, not a
  # DB column, so the filter resolves ids in memory via the presenter and then
  # constrains the scope — same approach as PortfolioCompanyDashboardController.
  #
  # `not_scored` matches failed runs only; companies with no report at all can't
  # appear in a report-backed table and are listed separately by _table.html.erb.
  #
  # Movement filters (improved / declined / unchanged / stale) cut across tiers
  # and are resolved by the presenter, so every figure on the Score Movement
  # panel opens the rows behind it.
  #
  # @param scope [ActiveRecord::Relation] base table scope
  # @param presenter [PortfolioScoringPresenter]
  # @param status [String, nil] tier slug or movement filter from params[:status]
  # @return [ActiveRecord::Relation]
  def filter_by_tier(scope, presenter, status)
    return scope if status.blank?

    scope.where(support_agent_reports: { id: presenter.reports_for_filter(status).map(&:id) })
  end

  # Resolves the "Run scoring on" selection into investor ids. Always re-queries
  # with entity scoping so tampered form data can't target another entity's
  # companies, and always requires a sector — without one the agent cannot match
  # a skill file and the run would fail immediately.
  #
  # @return [Array<Integer>]
  def resolve_target_ids
    base = portfolio_companies_scope.where.not(sector: [nil, ""])

    case params[:target_mode]
    when "selected"
      ids = Array(params[:target_ids]).map(&:to_i).reject(&:zero?)
      base.where(id: ids).pluck(:id)
    when "by_sector"
      sectors = Array(params[:target_sectors]).compact_blank
      sectors.any? ? base.in_sector(sectors).pluck(:id) : []
    when "by_tag"
      tags = Array(params[:target_tags]).compact_blank
      tags.any? ? base.with_tag_list(tags).pluck(:id) : []
    when "unscored"
      # Convenience mode: only the companies that have never been scored, so an
      # FM can fill the gaps without paying for a full re-run.
      unscored_investor_ids
    else
      base.pluck(:id)
    end
  end

  # Companies with a sector but no scoring report yet — the "unscored" run mode.
  # @return [Array<Integer>]
  def unscored_investor_ids
    # Must use the same window and predicate the presenter counts with, or the
    # label ("Only companies never scored (5)") and the run disagree: a company
    # scored 18 months ago, or one left with only a step-tracking row from a
    # crashed run, counted as never-run but was excluded from the run itself.
    reported_owner_ids = scoring_reports_scope.reselect(:owner_id).distinct.pluck(:owner_id)
    portfolio_companies_scope.where.not(sector: [nil, ""])
                             .where.not(id: reported_owner_ids)
                             .pluck(:id)
  end
end
