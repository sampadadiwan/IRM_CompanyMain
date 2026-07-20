# frozen_string_literal: true

# Standalone dashboard for Portfolio Company Agent compliance monitoring.
#
# Provides stat cards, compliance chart, company table with search/filter/pagination,
# and send reminders — decoupled from the generic SupportAgent framework.
#
# @see PortfolioDashboardPresenter
# @see PortfolioCompanyAgent
class PortfolioCompanyDashboardController < ApplicationController
  before_action :set_support_agent

  # GET /portfolio_company_dashboard
  #
  # Loads all portfolio reports for the presenter (stat cards, chart, sidebar),
  # then builds a separate filtered+paginated scope for the company table.
  # Two queries are intentional: presenter needs .includes(:owner), table needs .joins(:investor) for Ransack.
  #
  # @return [void]
  def show
    # Full report set for stat cards, chart, and sidebar aggregations
    portfolio_all = portfolio_reports_scope.includes(:owner).to_a
    @presenter = PortfolioDashboardPresenter.new(portfolio_all, @support_agent)

    # Filtered + paginated scope for the company table (Ransack search on investor name)
    table_scope = portfolio_reports_scope.joins(:investor)
    table_scope = filter_reports(table_scope, @presenter, params[:status])
    @q = table_scope.ransack(params[:q])
    @pagy, @paginated_reports = pagy(@q.result.order(updated_at: :desc), limit: 10)
    @status_filter = params[:status]
    @search_value = params.dig(:q, :investor_investor_name_cont)
  end

  # POST /portfolio_company_dashboard/send_reminders
  #
  # Sends KPI reminder emails to companies with missing KPI reports only.
  # Matches PortfolioCompanyAgent's send_kpi_reminder logic but without
  # the day-based guard (7/14/21) — manual button sends immediately.
  # Deduplicates via last_kpi_reminder_sent_at in report json_fields to
  # prevent multiple reminders on the same day.
  #
  # @return [void]
  def send_reminders
    # overdue_companies now returns only KPI-missing companies (not all blocked)
    overdue = @presenter_for_reminders.overdue_companies

    # Bulk-load reports and investors to avoid N+1 queries in the loop
    owner_ids = overdue.map { |c| c[:owner_id] } # rubocop:disable Rails/Pluck -- overdue is an array of hashes, not AR
    latest_reports = SupportAgentReport.where(support_agent: @support_agent, owner_id: owner_ids, owner_type: "Investor")
                                       .order(created_at: :desc).index_by(&:owner_id)
    investors = Investor.where(id: owner_ids).index_by(&:id)

    sent = 0
    skipped = 0
    overdue.each do |company|
      last_report = latest_reports[company[:owner_id]]
      last_sent = last_report&.json_fields&.dig("last_kpi_reminder_sent_at")
      if last_sent && Date.parse(last_sent) >= Time.zone.today
        skipped += 1
        next
      end

      investor = investors[company[:owner_id]]
      next unless investor

      EntityMailer.with(
        entity_id: investor.entity_id,
        requesting_entity_id: @support_agent.entity_id
      ).kpi_reminder.deliver_later

      if last_report
        last_report.json_fields["last_kpi_reminder_sent_at"] = Time.zone.today.iso8601
        last_report.save!
      end
      sent += 1
    end

    message = "Reminders sent to #{sent} overdue #{'company'.pluralize(sent)}."
    message += " #{skipped} already reminded today." if skipped.positive?

    redirect_to portfolio_company_dashboard_path, notice: message
  end

  private

  # @return [void]
  def set_support_agent
    @support_agent = SupportAgent.find_by!(
      agent_type: "PortfolioCompanyAgent",
      entity_id: current_user.entity_id
    )
    authorize @support_agent, :show?

    @bread_crumbs = {
      'Portfolio Company Dashboard': portfolio_company_dashboard_path
    }

    if action_name == "send_reminders"
      authorize @support_agent, :run?
      all_reports = portfolio_reports_scope.includes(:owner).to_a
      @presenter_for_reminders = PortfolioDashboardPresenter.new(all_reports, @support_agent)
    end
  end

  # @return [ActiveRecord::Relation]
  def portfolio_reports_scope
    SupportAgentReport.where(support_agent: @support_agent, owner_type: "Investor", latest: true)
                      .order(updated_at: :desc)
  end

  # Filters reports by status for the company table. Stat card clicks pass a status
  # param that maps to these filters. Filtering is done in-memory via the presenter
  # (not SQL) because statuses are computed from json_fields, not a DB column.
  #
  # Row 1 card filters: Complete, Pending, Incomplete, submitted (validated)
  # Row 2 card filters: kpi_overdue, valuation_overdue, documents_overdue
  # Action button filter: issues (all companies with any blocking issue)
  #
  # @param scope [ActiveRecord::Relation] base query to narrow
  # @param presenter [PortfolioDashboardPresenter] for computed status helpers
  # @param status [String, nil] filter key from params[:status]
  # @return [ActiveRecord::Relation] filtered scope
  def filter_reports(scope, presenter, status)
    return scope if status.blank?

    matching_ids = presenter.reports.select do |r|
      case status
      # Row 1 overview card filters
      when "Complete" then presenter.report_status(r) == "Up to Date"
      when "Pending" then presenter.report_status(r) == "Not Validated"
      when "submitted" then presenter.report_status(r).in?(["Up to Date", "Has Issues"])

      # "View Pending Issues" action button filter
      when "issues" then presenter.blocking_count(r).positive?
      # Row 2 category breakdown card filters
      when "kpi_overdue"
        Array(r.json_fields.with_indifferent_access[:kpi_issues]).any? { |i| i[:severity].to_s == "blocking" }
      when "valuation_overdue"
        Array(r.json_fields.with_indifferent_access[:valuation_issues]).any? { |i| i[:severity].to_s == "blocking" }
      when "documents_overdue"
        Array(r.json_fields.with_indifferent_access[:document_issues]).any? { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
      end
    end.map(&:id)

    scope.where(id: matching_ids)
  end
end
