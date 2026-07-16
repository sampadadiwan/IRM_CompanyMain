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
  # @return [void]
  def show
    portfolio_all = portfolio_reports_scope.includes(:owner).to_a
    @presenter = PortfolioDashboardPresenter.new(portfolio_all, @support_agent)

    table_scope = portfolio_reports_scope.joins(:investor)
    table_scope = filter_reports(table_scope, @presenter, params[:status])
    @q = table_scope.ransack(params[:q])
    @pagy, @paginated_reports = pagy(@q.result.order(updated_at: :desc), limit: 10)
    @status_filter = params[:status]
    @search_value = params.dig(:q, :investor_investor_name_cont)
  end

  # POST /portfolio_company_dashboard/send_reminders
  #
  # @return [void]
  def send_reminders
    overdue = @presenter_for_reminders.overdue_companies

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
    SupportAgentReport.where(support_agent: @support_agent, owner_type: "Investor")
                      .order(updated_at: :desc)
  end

  # @param scope [ActiveRecord::Relation]
  # @param presenter [PortfolioDashboardPresenter]
  # @param status [String, nil]
  # @return [ActiveRecord::Relation]
  def filter_reports(scope, presenter, status)
    return scope if status.blank?

    matching_ids = presenter.reports.select do |r|
      case status
      when "Complete"   then presenter.report_status(r) == "Complete"
      when "Pending"    then presenter.report_status(r) == "Pending"
      when "Incomplete" then presenter.report_status(r) == "Incomplete"
      when "submitted"  then presenter.report_status(r).in?(%w[Complete Incomplete])
      when "issues"     then presenter.blocking_count(r).positive?
      end
    end.map(&:id)

    scope.where(id: matching_ids)
  end
end
