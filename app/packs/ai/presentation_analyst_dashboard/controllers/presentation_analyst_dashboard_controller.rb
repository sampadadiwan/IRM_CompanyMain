# frozen_string_literal: true

# Standalone dashboard for PresentationAnalystAgent output — buckets every
# portfolio company into a Management Accountability tier and makes each
# tier a drill-down.
#
# Mirrors PortfolioScoringDashboardController's shape (stat cards, chart,
# filtered Turbo Frame table, footer) so every agent dashboard in the app
# behaves the same way for the FM. The one panel with no scoring-dashboard
# equivalent — portfolio-wide Cross-Period Flags — is computed entirely by
# PresentationAnalystPresenter; this controller only assembles the report
# scope it reads from.
#
# @see PresentationAnalystPresenter
# @see PresentationAnalystAgent
class PresentationAnalystDashboardController < ApplicationController
  helper PresentationAnalystDashboardHelper

  # Score and delta live inside json_fields, so the page is sorted in Ruby and
  # paginated from an Array, matching the scoring dashboard.
  require 'pagy/extras/array'

  before_action :set_support_agent

  # How far back to load analysis reports. Presentation analysis runs roughly
  # once per reporting period rather than continuously, so this window still
  # comfortably covers several runs per company.
  LOOK_BACK = 12.months

  SORTABLE_COLUMNS = %w[company sector score delta analyzed].freeze

  DEFAULT_SORT = "score"
  DEFAULT_DIRECTION = "asc"

  # Table-qualified for the same reason as the scoring dashboard: the table
  # scope joins :investor, and `investors` carries its own `id`, `json_fields`
  # and `created_at` columns — unqualified names raise "Column is ambiguous"
  # on MySQL.
  REPORT_COLUMNS = %w[
    id owner_id owner_type owner_name support_agent_id status json_fields created_at updated_at
  ].map { |column| "support_agent_reports.#{column}" }.freeze

  # GET /presentation_analyst_dashboard
  # @return [void]
  def show
    @status_filter = params[:status].presence
    @status_filter = nil unless PresentationAnalystPresenter.filter_slugs.include?(@status_filter)
    @sector_filter = params[:sector].presence
    @tag_filter = params[:tag].presence
    @search_value = params.dig(:q, :investor_investor_name_cont)

    @scoped_company_ids = scoped_company_ids

    all_reports = analysis_reports_scope.includes(:owner).to_a
    @presenter = PresentationAnalystPresenter.new(all_reports, @support_agent, company_ids: @scoped_company_ids)

    # Target selector data for the "Run analysis on" dropdown. Unlike scoring,
    # this agent needs no sector — it only needs KPI reports with a matching
    # presentation document — so every portfolio company is a valid target.
    @portfolio_companies = portfolio_companies_scope.order(:investor_name).pluck(:investor_name, :id)
    @total_portfolio_companies = portfolio_companies_scope.count

    @sectors_for_select = portfolio_companies_scope.pluck(:sector).compact
                                                   .map(&:strip).compact_blank
                                                   .tally.sort_by { |sector, _| sector }
    @tags_for_select = portfolio_companies_scope.pluck(:tag_list).compact
                                                .flat_map { |t| t.split(",") }
                                                .map(&:strip).compact_blank
                                                .tally.sort_by { |tag, _| tag }

    @sort = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
    @direction = params[:dir] == "desc" ? "desc" : DEFAULT_DIRECTION

    table_scope = analysis_reports_scope.joins(:investor).includes(:owner)
                                        .where(support_agent_reports: { id: @presenter.latest_report_ids })
    table_scope = filter_by_tier(table_scope, @presenter, @status_filter)
    @q = table_scope.ransack(params[:q])
    @pagy, @paginated_reports = pagy_array(sort_rows(@q.result.to_a), limit: 10)
  end

  # POST /presentation_analyst_dashboard/run_analysis
  # @return [void]
  def run_analysis
    authorize @support_agent, :run?

    target_ids = resolve_target_ids
    if target_ids.empty?
      redirect_to presentation_analyst_dashboard_path,
                  alert: "No portfolio companies matched that selection."
      return
    end

    SupportAgentJob.perform_later(
      support_agent_id: @support_agent.id,
      batch_ids: target_ids,
      batch_ids_type: "Investor",
      user_id: current_user.id,
      execution_mode: :adhoc_batch
    )

    redirect_to presentation_analyst_dashboard_path,
                notice: "Analysis started for #{target_ids.size} #{'company'.pluralize(target_ids.size)}. Results appear here as each run finishes."
  end

  private

  # @return [void]
  def set_support_agent
    @support_agent = SupportAgent.find_by!(
      agent_type: "PresentationAnalystAgent",
      entity_id: current_user.entity_id
    )
    authorize @support_agent, :show?

    @bread_crumbs = {
      'Presentation Analyst Dashboard': presentation_analyst_dashboard_path
    }
  end

  # Every presentation-analysis report for this agent inside the look-back
  # window. Excludes the step-tracking rows the agent also writes for the
  # same (owner, support_agent) pair via the same predicate structure the
  # scoring dashboard uses — step rows always carry a "steps" key, and a real
  # result row always carries "final_status".
  #
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def analysis_reports_scope
    SupportAgentReport
      .where(support_agent: @support_agent, owner_type: "Investor")
      .where(support_agent_reports: { created_at: LOOK_BACK.ago.. })
      .where(
        "support_agent_reports.json_fields LIKE '%\"final_status\":%' " \
        "AND support_agent_reports.json_fields NOT LIKE '%\"steps\":%'"
      )
      .select(*REPORT_COLUMNS)
      .order("support_agent_reports.created_at DESC")
      .then { |scope| @scoped_company_ids ? scope.where(owner_id: @scoped_company_ids) : scope }
  end

  # @return [Array<Integer>, nil]
  def scoped_company_ids
    return nil if @sector_filter.blank? && @tag_filter.blank?

    scope = portfolio_companies_scope
    scope = scope.in_sector([@sector_filter]) if @sector_filter.present?
    scope = scope.with_tag_list([@tag_filter]) if @tag_filter.present?
    scope.pluck(:id)
  end

  # @param reports [Array<SupportAgentReport>]
  # @return [Array<SupportAgentReport>]
  def sort_rows(reports)
    keyed = reports.map { |report| [sort_key(report), report] }
    present_rows, missing_rows = keyed.partition { |key, _| !key.nil? }

    present_rows = present_rows.sort_by(&:first)
    present_rows = present_rows.reverse if @direction == "desc"

    (present_rows + missing_rows).map(&:last)
  end

  # @param report [SupportAgentReport]
  # @return [Comparable, nil]
  def sort_key(report)
    case @sort
    when "company"  then @presenter.company_name(report).to_s.downcase
    when "sector"   then @presenter.sector_for(report).to_s.downcase.presence
    when "delta"    then @presenter.delta_for(report)
    when "analyzed" then report.created_at
    else @presenter.score_for(report)
    end
  end

  # @return [ActiveRecord::Relation<Investor>]
  def portfolio_companies_scope
    Investor.where(entity_id: current_user.entity_id)
            .where("LOWER(category) = ?", "portfolio company")
  end

  # @param scope [ActiveRecord::Relation]
  # @param presenter [PresentationAnalystPresenter]
  # @param status [String, nil]
  # @return [ActiveRecord::Relation]
  def filter_by_tier(scope, presenter, status)
    return scope if status.blank?

    scope.where(support_agent_reports: { id: presenter.reports_for_filter(status).map(&:id) })
  end

  # Resolves the "Run analysis on" selection into investor ids. Always
  # re-queries with entity scoping so tampered form data can't target another
  # entity's companies.
  #
  # @return [Array<Integer>]
  def resolve_target_ids
    base = portfolio_companies_scope

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
    when "unanalyzed"
      unanalyzed_investor_ids
    else
      base.pluck(:id)
    end
  end

  # Companies with no presentation-analysis report yet — the "unanalyzed" run mode.
  # @return [Array<Integer>]
  def unanalyzed_investor_ids
    reported_owner_ids = analysis_reports_scope.unscope(:order)
                                               .reselect(:owner_id)
                                               .distinct
                                               .pluck(:owner_id)
    portfolio_companies_scope.where.not(id: reported_owner_ids).pluck(:id)
  end
end
