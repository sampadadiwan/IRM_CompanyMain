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
  # Also computes the look-back period info for the window status indicator bar.
  #
  # Two queries are intentional: presenter needs .includes(:owner),
  # table needs .joins(:investor) for Ransack.
  #
  # @return [void]
  def show
    # Compute the look-back period for the window status indicator.
    # Uses PortfolioCompanyAgent's compute_check_period to determine
    # the active window (T+start to T+end) and the data query range.
    # Also stores due_period in the hash for the "closed" state's
    # next-window computation in _window_status.html.erb.
    agent_instance = PortfolioCompanyAgent.new
    agent_instance.instance_variable_set(:@support_agent, @support_agent)
    @period_info = agent_instance.send(:compute_check_period)
    @period_info[:due_period] = @support_agent.json_fields["due_period"] || "Quarter"

    # Report set for stat cards, chart, and sidebar aggregations.
    # When the last run targeted a subset of companies, scope the presenter
    # to only those companies so stat cards reflect the run — unless the FM
    # clicks "Show All" (passes show_all=1 query param).
    # @see PortfolioValidationJob where last_run_target_ids is persisted
    portfolio_all = portfolio_reports_scope.includes(:owner)
    last_run_ids = @support_agent.json_fields["last_run_target_ids"]
    @showing_all = params[:show_all] == "1" || last_run_ids.blank?
    portfolio_all = portfolio_all.where(owner_id: last_run_ids) if !@showing_all && last_run_ids.present?
    portfolio_all = portfolio_all.to_a
    @presenter = PortfolioDashboardPresenter.new(portfolio_all, @support_agent)

    # Target selector data for the Run Validation action's "Run on" dropdown.
    # Queries portfolio company names/IDs, tags, and sectors so the FM can
    # scope validation to specific companies instead of running on all.
    # Mirrors the pattern in InvestorsController for the selective run page.
    #
    # @see #run_validation for how these selections are resolved to target IDs
    base_portcos = Investor.where(entity_id: current_user.entity_id)
                           .where("LOWER(category) = ?", "portfolio company")
    @portfolio_companies = base_portcos.order(:investor_name).pluck(:investor_name, :id)
    # Tags with company counts — e.g., [["SaaS", 3], ["FinTech", 1]]
    # Split comma-separated tag_list, count occurrences per unique tag.
    @tags_for_select = base_portcos.pluck(:tag_list).compact
                                   .flat_map { |t| t.split(",") }
                                   .map(&:strip).compact_blank
                                   .tally.sort_by { |tag, _| tag }

    # Sectors with company counts — e.g., [["Technology", 2], ["Healthcare", 1]]
    @sectors_for_select = base_portcos.pluck(:sector).compact
                                      .flat_map { |s| s.split(",") }
                                      .map(&:strip).compact_blank
                                      .tally.sort_by { |sector, _| sector }

    # Filtered + paginated scope for the company table (Ransack search on investor name).
    # Applies the same last_run_target_ids filter as the stat cards so the table
    # matches the stats. Cleared when the FM clicks "Show all".
    table_scope = portfolio_reports_scope.joins(:investor)
    table_scope = table_scope.where(owner_id: last_run_ids) if !@showing_all && last_run_ids.present?
    table_scope = filter_reports(table_scope, @presenter, params[:status])
    @q = table_scope.ransack(params[:q])
    @pagy, @paginated_reports = pagy(@q.result.order(updated_at: :desc), limit: 10)
    @status_filter = params[:status]
    @search_value = params.dig(:q, :investor_investor_name_cont)
  end

  # POST /portfolio_company_dashboard/run_validation
  #
  # Enqueues a PortfolioValidationJob to run PortfolioCompanyAgent. Accepts an
  # optional check_as_on_date from the period dropdown and target_mode from the
  # target selector. When target_mode is not "all", resolves the FM's selection
  # (company IDs, tags, or sectors) into validated investor IDs scoped to the
  # current entity.
  #
  # Uses PortfolioValidationJob (not the shared SupportAgentJob) because the
  # shared job doesn't accept agent-specific parameters like check_as_on_date.
  #
  # @return [void]
  # @see #resolve_target_ids
  def run_validation
    authorize @support_agent, :run?
    check_date = params[:check_as_on_date].presence
    target_ids = resolve_target_ids

    # Guard: FM used selectors but no companies matched the combination.
    # Without this, empty resolves to nil downstream and the job runs on ALL companies.
    if target_ids.is_a?(Array) && target_ids.empty?
      render json: { error: "No companies matched your tag/sector/company selection." }, status: :unprocessable_entity
      return
    end

    # Invert the UI's positive "Send reminders" checkbox into the pipeline's
    # skip_reminders flag. Only an explicit "1" (checked) enables sending.
    # When the agent-level toggle is off the checkbox is hidden and the param
    # is absent, so skip_reminders defaults to true.
    skip_reminders = params[:send_reminders].to_s != "1"

    PortfolioValidationJob.perform_later(
      support_agent_id: @support_agent.id,
      user_id: current_user.id,
      entity_id: current_user.entity_id,
      check_as_on_date: check_date,
      target_ids: target_ids,
      skip_reminders: skip_reminders
    )

    head :ok
  end

  # POST /portfolio_company_dashboard/send_reminders
  #
  # Sends consolidated reminder emails to companies with blocking issues.
  # Each email lists only the missing items (KPIs, Documents, Valuations).
  # Manual button sends immediately — no window gate.
  # Deduplicates via last_kpi_reminder_sent_at in report json_fields to
  # prevent multiple reminders on the same day.
  #
  # @return [void]

  def send_reminders
    # Guard: bail early if no explicit recipients configured on the agent.
    # Changed from the previous behaviour where the mailer fell back to
    # @entity.employees (fund team) — reminders must only go to the
    # FM-configured email list stored in json_fields["kpi_reminder_recipients"].
    recipients = @support_agent.json_fields["kpi_reminder_recipients"].to_s.strip
    if recipients.blank?
      flash[:alert] = "No recipient emails configured. Add recipients in the agent settings."
      redirect_to portfolio_company_dashboard_path
      return
    end

    overdue = @presenter_for_reminders.overdue_companies

    # Filter to FM-selected companies when the modal posts selected_ids[].
    # Falls back to all overdue companies if no selection (shouldn't happen
    # with the modal UI, but guards against direct POST).
    selected = Array(params[:selected_ids]).map(&:to_i).reject(&:zero?)
    if selected.present?
      selected_set = selected.to_set
      overdue = overdue.select { |c| selected_set.include?(c[:owner_id]) }
    end

    # Bulk-load reports and investors to avoid N+1 queries in the loop
    owner_ids = overdue.map { |c| c[:owner_id] } # rubocop:disable Rails/Pluck -- overdue is an array of hashes, not AR
    latest_reports = SupportAgentReport.where(support_agent: @support_agent, owner_id: owner_ids, owner_type: "Investor")
                                       .order(created_at: :desc).index_by(&:owner_id)
    investors = Investor.where(id: owner_ids).index_by(&:id)

    sent = 0
    skipped_today = 0
    skipped_optout = 0
    overdue.each do |company|
      last_report = latest_reports[company[:owner_id]]
      last_sent = last_report&.json_fields&.dig("last_kpi_reminder_sent_at")
      if last_sent && Date.parse(last_sent) >= Time.zone.today
        skipped_today += 1
        next
      end

      investor = investors[company[:owner_id]]
      next unless investor

      # Skip companies that have opted out of KPI reminders via custom form field.
      if investor.json_fields["skip_kpi_reminder"].to_s.downcase.in?(%w[yes true 1])
        skipped_optout += 1
        next
      end

      # Build missing items from the report's stored issues.
      data = last_report&.json_fields&.with_indifferent_access || {}
      missing_items = []
      missing_items << "KPIs" if Array(data[:kpi_issues]).any? { |i| i[:severity].to_s == "blocking" }
      missing_items << "Documents" if Array(data[:document_issues]).any? { |i| i[:severity].to_s == "blocking" }
      missing_items << "Valuations" if Array(data[:valuation_issues]).any? { |i| i[:severity].to_s == "blocking" }
      missing_items = ["KPIs"] if missing_items.empty?

      # Pass explicit recipient_emails so the mailer uses the FM-configured
      # contacts instead of falling back to entity employees.
      EntityMailer.with(
        entity_id: investor.entity_id,
        requesting_entity_id: @support_agent.entity_id,
        missing_items: missing_items,
        period_label: data[:period_label],
        recipient_emails: recipients
      ).kpi_reminder.deliver_later

      if last_report
        last_report.json_fields["last_kpi_reminder_sent_at"] = Time.zone.today.iso8601
        last_report.save!
      end
      sent += 1
    end

    # Flash feedback with separate counts for same-day dedup vs company opt-out
    # so the FM knows exactly why reminders were not sent.
    if sent.positive?
      msg = "Reminders sent to #{sent} #{'company'.pluralize(sent)}."
      msg += " #{skipped_optout} opted out." if skipped_optout.positive?
      msg += " #{skipped_today} already sent today." if skipped_today.positive?
      flash[:notice] = msg
    elsif skipped_today.positive? || skipped_optout.positive?
      parts = []
      parts << "#{skipped_today} already sent today" if skipped_today.positive?
      parts << "#{skipped_optout} opted out of reminders" if skipped_optout.positive?
      flash[:alert] = "No new reminders sent. #{parts.join(', ')}."
    else
      flash[:alert] = "No overdue companies to send reminders to."
    end

    redirect_to portfolio_company_dashboard_path
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

  # Resolves target company IDs from the Select2 multi-select params.
  # Supports any combination of tags, sectors, and explicit company IDs.
  # Tags and sectors are AND'd when both present (company must match both);
  # explicit company IDs are always included additively.
  # Re-queries with entity_id scoping to prevent targeting companies
  # in other entities via tampered form data.
  #
  # @return [Array<Integer>] investor IDs to validate (empty if selectors matched nothing)
  # @return [nil] when no selectors were used — means "all companies"
  def resolve_target_ids
    base = Investor.where(entity_id: current_user.entity_id)
                   .where("LOWER(category) = ?", "portfolio company")

    tags = Array(params[:target_tags]).compact_blank
    sectors = Array(params[:target_sectors]).compact_blank
    explicit_ids = Array(params[:target_ids]).map(&:to_i).reject(&:zero?)

    # No selectors used → nil means "all companies"
    return nil if tags.blank? && sectors.blank? && explicit_ids.blank?

    resolved = Set.new

    # Explicit company IDs are always included (additive, bypass tag/sector AND)
    resolved.merge(base.where(id: explicit_ids).pluck(:id)) if explicit_ids.present?

    # Tags + sectors AND'd when both present; OR within each group
    if tags.present? && sectors.present?
      tag_ids = base.with_tag_list(tags).pluck(:id)
      sector_ids = base.in_sector(sectors).pluck(:id)
      resolved.merge(tag_ids & sector_ids)
    elsif tags.present?
      resolved.merge(base.with_tag_list(tags).pluck(:id))
    elsif sectors.present?
      resolved.merge(base.in_sector(sectors).pluck(:id))
    end

    resolved.to_a
  end
end
