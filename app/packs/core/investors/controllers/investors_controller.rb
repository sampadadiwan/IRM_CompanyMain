class InvestorsController < ApplicationController
  helper InvestorAnalyticsHelper
  before_action :set_investor, only: %w[show update destroy edit dashboard generate_reports kpi_data_preview portfolio_investments_report generate_agent_charts portfolio_analytics]
  after_action :verify_authorized, except: %i[merge portfolio_investments_report_all]

  # GET /investors or /investors.json
  def index
    @bread_crumbs = { Stakeholders: investors_path }
    template = "investors/index"
    authorize(Investor)

    fetch_rows

    if params[:multi_portfolio_dashboard].present?
      setup_portfolio_dashboard
      template = "investors/multi_portfolio_dashboard"
    elsif params[:portfolio_agent_run].present?
      setup_portfolio_agent_run
      template = "investors/portfolio_agent_run"
    end

    respond_to do |format|
      format.html { render template }
      format.turbo_stream
      format.xlsx
      format.json
    end
  end

  def analytics
    authorize(Investor)
    fetch_rows
    render "investors/analytics_content", layout: false
  end

  # GET /investors/:id/portfolio_analytics
  def portfolio_analytics
    if params[:type] == "LPFlow"
      render "investors/lp_flow_analytics_content", layout: false
    else
      @apis = AggregatePortfolioInvestment.where(portfolio_company_id: @investor.id)
      render "investors/portfolio_analytics_content", layout: false
    end
  end

  def fetch_rows
    @q = Investor.ransack(params[:q])
    @investors = policy_scope(@q.result)

    if params[:multi_portfolio_dashboard].present? || params[:portfolio_agent_run].present?
      # Get portfolio companies first
      base_investors = current_user.entity.investors.portfolio_companies

      # Build tags and sectors options from ALL portfolio companies (before filtering)
      @tags_for_select = base_investors.pluck(:tag_list).compact.flat_map { |t| t.split(",") }.map(&:strip).uniq.compact_blank.sort
      @sectors_for_select = base_investors.pluck(:sector).compact.flat_map { |s| s.split(",") }.map(&:strip).uniq.compact_blank.sort

      # Now apply filters
      @investors = @investors.portfolio_companies
      @investors = @investors.with_tag_list(params[:tag_list]) if params[:tag_list].present?
      @investors = @investors.in_sector(params[:sector]) if params[:sector].present?
    end

    @investors = InvestorSearch.search(@investors, params, current_user)

    @all_investors = @investors
    @pagy, @investors = pagy(@investors, limit: params[:per_page]) if params[:multi_portfolio_dashboard].blank? && params[:portfolio_agent_run].blank? && params[:all].blank?

    # For portfolio_agent_run, fetch last run times efficiently
    @investors = @investors.includes(:support_agent_report) if params[:portfolio_agent_run].present?
  end

  def portfolio_investments_report
    if request.post? && params[:as_of].present?
      portfolio_company_id = @investor.id
      PortfolioInvestmentsXlReportJob.perform_later(params[:as_of], current_user.id, portfolio_company_id:)
      redirect_to investor_path(@investor, tab: 'docs-tab'), notice: "Report generation started, please check back in a few mins"
    else
      render "portfolio_investments_report"
    end
  end

  def portfolio_investments_report_all
    if request.post? && params[:as_of].present?
      PortfolioInvestmentsXlReportJob.perform_later(params[:as_of], current_user.id, fund_id: params[:fund_id])
      if params[:fund_id].present?
        redirect_to fund_path(params[:fund_id], tab: 'docs-tab'), notice: "Report generation started, please check back in a few mins"
      else
        redirect_to investors_path, notice: "Report generation started, please check back in a few mins"
      end
    else
      render "portfolio_investments_report"
    end
  end

  def generate_agent_charts
    load_applicable_agent_charts

    if request.post?
      if params[:agent_chart_id].present?
        # Single chart selected from the dropdown.
        chart = @applicable_charts.find(params[:agent_chart_id])
        AgentChartJob.perform_later(current_user.id,
                                    agent_chart_id: chart.id,
                                    portfolio_company_id: @investor.id)
        notice = "Generating \"#{chart.title}\" for #{@investor.investor_name}…"
      else
        # No specific chart — queue every applicable chart for this portfolio company.
        @applicable_charts.each do |chart|
          AgentChartJob.perform_later(current_user.id,
                                      agent_chart_id: chart.id,
                                      portfolio_company_id: @investor.id)
        end
        notice = "Generating #{@applicable_charts.size} #{'chart'.pluralize(@applicable_charts.size)} for #{@investor.investor_name}…"
      end

      redirect_to investor_path(@investor), notice: notice
    end
  end

  # GET /investors/:id/kpi_data_preview — AJAX: returns how many KPI periods exist for the
  # chosen period_type / kpi_tag / end_date combination, so the form can warn before submit.
  def kpi_data_preview
    authorize @investor, :kpi_data_preview?
    period_type = params[:kpi_period_type].presence || "Monthly"
    kpi_tag     = params[:kpi_tag].presence         || "Actual"
    end_date    = begin
      Date.parse(params[:end_date])
    rescue StandardError
      Time.zone.today
    end
    n_requested = params[:n_periods].to_i.clamp(1, 24)

    reports = KpiReport
              .where(portfolio_company: @investor,
                     entity: @investor.entity,
                     period: period_type,
                     tag_list: kpi_tag)
              .where(as_of: ..end_date)
              .order(as_of: :desc)
              .limit(n_requested)
              .pluck(:as_of)

    labels = reports.reverse.map do |d|
      period_type == "Monthly" ? d.strftime("%b %Y") : "Q#{((d.month - 1) / 3) + 1} #{d.year}"
    end

    render json: { count: reports.length, requested: n_requested, labels: labels }
  end

  def generate_reports
    authorize @investor, :generate_reports?

    if request.post?
      template = PortfolioReportTemplate.find(params[:portfolio_report_template_id])

      draft = PortfolioReportDraft.create!(
        portfolio_company: @investor,
        portfolio_report: template.portfolio_report,
        portfolio_report_template: template,
        user: current_user,
        start_date: params[:start_date],
        end_date: params[:end_date],
        kpi_period_type: params[:kpi_period_type],
        kpi_tag: params[:kpi_tag],
        n_periods: params[:n_periods],
        selected_kpi_mapping_ids: params[:selected_kpi_mapping_ids],
        status: :configuring
      )

      PortfolioReportDraftJob.perform_later(draft.id)

      redirect_to portfolio_report_draft_path(draft), notice: "Generating your report draft — we'll notify you when it's ready to review."
    else
      all_reports = @investor.entity.portfolio_reports
                             .includes(portfolio_report_templates: :style_document,
                                       portfolio_report_sections: [])
      # Split into ready (sections + at least one template) vs incomplete (shown in setup roadmap only)
      @ready_portfolio_reports, @incomplete_portfolio_reports = all_reports.partition { |r| r.portfolio_report_sections.any? && r.portfolio_report_templates.any? }
      @portfolio_reports          = @ready_portfolio_reports # used by the Stimulus template-dropdown script
      @kpi_mappings               = @investor.investor_kpi_mappings.show_in_report.group_by(&:category)
      # Pre-fill dates/settings from the most recent draft for this portco
      @last_draft                 = PortfolioReportDraft.where(portfolio_company: @investor)
                                                        .order(created_at: :desc).first
      @start_date                 = @last_draft&.start_date  || (Time.zone.today - 3.months).beginning_of_month
      @end_date                   = @last_draft&.end_date    || Time.zone.today.end_of_month
      @default_n_periods          = @last_draft&.n_periods   || 6
      @default_kpi_period_type    = @last_draft&.kpi_period_type
      @default_kpi_tag            = @last_draft&.kpi_tag
      @default_kpi_mapping_ids    = @last_draft&.selected_kpi_mapping_ids || []
      render "generate_reports"
    end
  end

  def dashboard
    @dashboard_name = params[:dashboard_name]
    @dashboard_name ||= @investor.category == "Portfolio Company" ? "Portfolio Company Dashboard" : "Investor Dashboard"
    @favorite_title = "#{@investor.investor_name} Dashboard"
    @favorite_url = dashboard_investor_path(id: @investor.id)
    @dashboard_names, @name = resolve_dashboard(@dashboard_name, params[:name])
    @logo = @investor.logo_doc&.file
  end

  def setup_portfolio_dashboard
    @dashboard_name = "Aggregated Portfolio Dashboard"
    @dashboard_names, @name = resolve_dashboard(@dashboard_name, params[:name])
    params[:filter] = true
    @favorite_title = "Portfolio Dashboard"
    @favorite_url = investors_path(multi_portfolio_dashboard: true)

    # Initialize empty arrays - will be populated in index method
    @tags_for_select ||= []
    @setup_portfolio_dashboard ||= []
  end

  def setup_portfolio_agent_run
    @page_title = "Portfolio Agent Run"
    @name = params[:name] || "Default"
    params[:filter] = true

    # Initialize empty arrays - will be populated in index method
    @tags_for_select ||= []
    @sectors_for_select ||= []

    # Get available support agents for the current entity
    @support_agents = SupportAgent.where(entity_id: current_user.entity_id)
                                  .order(:name)

    # Efficiently get last run time for each company using a LEFT JOIN
    @last_run_times = {}
  end

  def report_detail
    begin
      @investor = Investor.find(params[:investor_id])
      authorize @investor
      @report_type = params[:report_type] # 'kpi', 'valuation', or 'document'
      @report = SupportAgentReport.latest_only.find_by(owner: @investor)
    rescue StandardError => e
      Rails.logger.error "Error in report_detail: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @investor = nil
      @report = nil
      @error = e.message
    end

    respond_to do |format|
      format.html { render "report_detail", layout: false }
    end
  end

  def multi_portfolio_stat_currency
    investor_ids = Array(params[:investor_ids]).map(&:to_i).reject(&:zero?)

    # Apply policy scope first to ensure tenant isolation, then filter to requested ids
    @investors = policy_scope(Investor).where(id: investor_ids)

    authorize Investor, :index?

    @selected_fund_ids = Array(params[:fund_ids]).map(&:to_i).reject(&:zero?)

    # Mirror the locals passed by widgets/_stats.html.erb for the multi-portfolio case
    fields = params[:fields].present? ? params[:fields].split(",").map(&:strip) : []
    decimals = params[:decimals]&.to_i || 2
    force_units = params[:force_units] || current_user.entity.default_currency_units
    tracking_currency = params[:tracking_currency].presence || current_user.entity.tracking_currency
    currency = params[:currency].presence
    widget_id = params[:widget_id].presence

    render partial: "aggregate_portfolio_investments/stats_for_multiple_portfolio_companies",
           locals: {
             show_currency_filter: true,
             fields: fields,
             decimals: decimals,
             force_units: force_units,
             tracking_currency: tracking_currency,
             currency: currency,
             widget_size: params[:widget_size].presence || "col-md-12",
             widget_id: widget_id
           }
  end

  def merge
    @entity = current_user.has_cached_role?(:super) ? Entity.find(params[:entity_id]) : current_user.entity
    if request.get?
      render "merge"
    else
      old_investor = Investor.find(params[:old_investor_id])
      new_investor = Investor.find(params[:new_investor_id])
      authorize(old_investor, :update?)
      authorize(new_investor, :update?)

      InvestorMergeJob.perform_later(old_investor.id, new_investor.id, current_user.id)
      redirect_to investor_url(new_investor), notice: "Stakeholder merge in progress, please check back in a few mins"
    end
  end

  def search
    authorize(Investor)
    query = params[:query]
    if query.present?
      @investors = InvestorIndex.filter(term: { entity_id: current_user.entity_id })
                                .query(simple_query_string: { fields: InvestorIndex::SEARCH_FIELDS,
                                                              query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to investors_path
    end
  end

  # GET /investors/1 or /investors/1.json
  def show; end

  # GET /investors/new
  def new
    @bread_crumbs = { Stakeholders: investors_path, New: nil }
    @investor = Investor.new(investor_params)
    authorize @investor
    setup_custom_fields(@investor)

    @frame = params[:turbo_frame] || "new_deal_investor"
    if params[:turbo]
      render turbo_stream: [
        turbo_stream.replace(@frame, partial: "investors/board_form", locals: { investor: @investor, frame: @frame })
      ]
    end
  end

  # GET /investors/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    setup_custom_fields(@investor)
  end

  # POST /investors or /investors.json
  def create
    @investor = Investor.new(investor_params)
    @investor.entity_id = current_user.entity_id
    authorize(@investor)

    respond_to do |format|
      if @investor.save
        @investor.document_folder if @investor.category == 'Portfolio Company' && params[:return_to].present?
        redirect_url = params[:back_to].presence || investor_url(@investor)
        format.turbo_stream do
          @frame = params[:turbo_frame] || params[:investor][:turbo_frame] || "new_deal_investor"
          UserAlert.new(user_id: current_user.id, message: "Stakeholder was successfully created!", level: "success").broadcast
          if params[:redirect_frame_to].present?
            # Explicit redirect URL for the turbo frame
            render turbo_stream: [
              turbo_stream.replace(@frame, html: helpers.turbo_frame_tag(@frame, src: params[:redirect_frame_to]))
            ]
          else
            partial = params[:back_to].presence || "investors/board_form"
            render turbo_stream: [
              turbo_stream.replace(@frame, partial:, locals: { frame: @frame, investor: @investor })
            ]
          end
        end
        return_to = params[:return_to]
        # Redirect back to AI Portfolio Reports form with new investor pre-selected

        if return_to.present?
          return_to = "#{return_to}#{return_to.include?('?') ? '&' : '?'}portfolio_company_id=#{@investor.id}"
        end
        format.html { redirect_to (return_to || redirect_url), notice: "Stakeholder was successfully created." }

        format.json { render :show, status: :created, location: @investor }
      else
        logger.debug @investor.errors.full_messages

        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor.errors, status: :unprocessable_entity }
        format.turbo_stream do
          @frame = params[:turbo_frame] || params[:investor][:turbo_frame] || "new_deal_investor"
          @alert = "Stakeholder could not be created!"
          @alert += " #{@investor.errors.full_messages.join(', ')}"
          render turbo_stream: [
            turbo_stream.prepend(@frame, partial: "layouts/alerts", locals: { alert: @alert })
          ]
        end
      end
    end
  end

  # PATCH/PUT /investors/1 or /investors/1.json
  def update
    respond_to do |format|
      if @investor.update(investor_params)
        format.html { redirect_to investor_url(@investor), notice: "Stakeholder was successfully updated." }
        format.json { render :show, status: :ok, location: @investor }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investors/1 or /investors/1.json
  def destroy
    @investor.destroy

    respond_to do |format|
      format.html { redirect_to investors_url, notice: "Stakeholder was successfully deleted." }
      format.json { head :no_content }
    end
  end

  private

  # Loads AgentCharts that apply to this portfolio company:
  #   - charts with no tag_list apply to every portfolio company
  #   - charts whose tag_list shares at least one tag with the portco's tag_list
  def load_applicable_agent_charts
    portco_tags = @investor.tag_list.to_s.split(",").map(&:strip).compact_blank
    base = AgentChart.where(entity: @investor.entity).order(:title)

    @applicable_charts = if portco_tags.any?
                           tag_conditions = portco_tags.map { "tag_list LIKE ?" }.join(" OR ")
                           base.where("tag_list IS NULL OR tag_list = '' OR (#{tag_conditions})",
                                      *portco_tags.map { |t| "%#{t}%" })
                         else
                           # Portco has no tags — only untagged charts (which apply to all) are relevant.
                           base.where("tag_list IS NULL OR tag_list = ''")
                         end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_investor
    @investor = Investor.find(params[:id])
    authorize @investor
    @bread_crumbs = { Stakeholders: investors_path, "#{@investor.investor_name}": investor_path(@investor) }
  end

  # Only allow a list of trusted parameters through.
  def investor_params
    params.require(:investor).permit(:investor_entity_id, :tag_list, :investor_name, :form_type_id, :sector,
                                     :pan, :entity_id, :category, :city, :primary_email, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
