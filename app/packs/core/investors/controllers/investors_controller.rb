class InvestorsController < ApplicationController
  before_action :set_investor, only: %w[show update destroy edit dashboard generate_reports portfolio_investments_report]
  after_action :verify_authorized, except: %i[merge portfolio_investments_report_all]

  # GET /investors or /investors.json
  def index
    template = "investors/index"
    authorize(Investor)

    if params[:multi_portfolio_dashboard].present?
      setup_portfolio_dashboard
      template = "investors/multi_portfolio_dashboard"
    elsif params[:portfolio_agent_run].present?
      setup_portfolio_agent_run
      template = "investors/portfolio_agent_run"
    end

    @q = Investor.ransack(params[:q])
    @investors = policy_scope(@q.result)

    if params[:multi_portfolio_dashboard].present? || params[:portfolio_agent_run].present?
      # Get portfolio companies first
      base_investors = @investors.portfolio_companies

      # Build tags and sectors options from ALL portfolio companies (before filtering)
      @tags_for_select = base_investors.pluck(:tag_list).map { |tag_list| tag_list&.split(",")&.map(&:strip) }.flatten.uniq.compact_blank.sort
      @sectors_for_select = base_investors.pluck(:sector).map { |sectors| sectors&.split(",")&.map(&:strip) }.flatten.uniq.compact_blank.sort

      # Now apply filters
      @investors = base_investors
      @investors = @investors.with_tag_list(params[:tag_list]) if params[:tag_list].present?
      @investors = @investors.in_sector(params[:sector]) if params[:sector].present?
    end

    @investors = InvestorSearch.search(@investors, params, current_user)

    @pagy, @investors = pagy(@investors, limit: params[:per_page]) if params[:multi_portfolio_dashboard].blank? && params[:portfolio_agent_run].blank? && params[:all].blank?

    # For portfolio_agent_run, fetch last run times efficiently
    if params[:portfolio_agent_run].present?
      investor_ids = @investors.pluck(:id)
      @last_run_times = SupportAgentReport
        .where(owner_type: 'Investor', owner_id: investor_ids)
        .group(:owner_id)
        .maximum(:updated_at)
    end

    respond_to do |format|
      format.html { render template }
      format.turbo_stream
      format.xlsx
      format.json
    end
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

  def generate_reports
    if request.post?

      if params[:kpi_report].present?
        kpi_report = params[:kpi_report]
        # This come as a set of arrays of periods and dates, we convert it to a hash
        kpi_reports_map = kpi_report["period"].each_with_index.map do |period, index|
          { period: period, as_of: kpi_report["as_of"][index], add_docs: kpi_report["add_docs"][index] }
        end
      end
      # Generate the report if this is a post request
      PortfolioReportJob.perform_later(params[:portfolio_report_id], params[:start_date], params[:end_date], current_user.id, portfolio_company_id: @investor.id, kpi_reports_map: kpi_reports_map)

      redirect_to investor_path(@investor, tab: 'docs-tab'), notice: "Report generation started, please check back in a few mins"
    else
      # Show the form to generate the report
      render "generate_reports"
    end
  end

  def dashboard
    @dashboard_name = params[:dashboard_name]
    @dashboard_name ||= @investor.category == "Portfolio Company" ? "Portfolio Company Dashboard" : "Investor Dashboard"
    @name = params[:name] || "Default"
  end

  def setup_portfolio_dashboard
    @dashboard_name = "Aggregated Portfolio Dashboard"
    @name = params[:name] || "Default"
    params[:filter] = true

    # Initialize empty arrays - will be populated in index method
    @tags_for_select = []
    @sectors_for_select = []
  end

  def setup_portfolio_agent_run
    @page_title = "Portfolio Agent Run"
    @name = params[:name] || "Default"
    params[:filter] = true

    # Initialize empty arrays - will be populated in index method
    @tags_for_select = []
    @sectors_for_select = []

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
      @report = SupportAgentReport.find_by(owner: @investor)
    rescue => e
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
      redirect_to investor_url(new_investor), notice: "Investor merge in progress, please check back in a few mins"
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
          partial = params[:back_to].presence || "investors/board_form"
          UserAlert.new(user_id: current_user.id, message: "Investor was successfully created!", level: "success").broadcast
          render turbo_stream: [
            turbo_stream.replace(@frame, partial:, locals: { frame: @frame, investor: @investor })
          ]
        end
        return_to = params[:return_to]
        # Redirect back to AI Portfolio Reports form with new investor pre-selected

        if return_to.present?
          return_to = "#{return_to}#{return_to.include?('?') ? '&' : '?'}portfolio_company_id=#{@investor.id}"
        end
        format.html { redirect_to (return_to || redirect_url), notice: "Investor was successfully created." }

        format.json { render :show, status: :created, location: @investor }
      else
        logger.debug @investor.errors.full_messages

        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor.errors, status: :unprocessable_entity }
        format.turbo_stream do
          @frame = params[:turbo_frame] || params[:investor][:turbo_frame] || "new_deal_investor"
          @alert = "Investor could not be created!"
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
        format.html { redirect_to investor_url(@investor), notice: "Investor was successfully updated." }
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
      format.html { redirect_to investors_url, notice: "Investor was successfully deleted." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor
    @investor = Investor.find(params[:id])
    authorize @investor
    @bread_crumbs = { Investors: investors_path, "#{@investor.investor_name}": investor_path(@investor) }
  end

  # Only allow a list of trusted parameters through.
  def investor_params
    params.require(:investor).permit(:investor_entity_id, :tag_list, :investor_name, :form_type_id, :sector,
                                     :pan, :entity_id, :category, :city, :primary_email, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
