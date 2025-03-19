class InvestorsController < ApplicationController
  before_action :set_investor, only: %w[show update destroy edit dashboard generate_reports portfolio_investments_report]
  after_action :verify_authorized, except: [:merge]

  # GET /investors or /investors.json
  def index
    @q = Investor.ransack(params[:q])
    @investors = policy_scope(@q.result)
    authorize(Investor)
    @investors = InvestorSearch.search(@investors, params, current_user)
    if params[:all].blank?
      @investors = @investors.page(params[:page])
      @investors = @investors.per(params[:per_page].to_i) if params[:per_page].present?
    end
    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json { render json: InvestorDatatable.new(params, investors: @investors) }
    end
  end

  def portfolio_investments_report
    if request.post? && params[:as_of].present?
      portfolio_company_id = if params[:all].present?
                               nil
                             else
                               @investor.id
                             end
      PortfolioInvestmentsXlReportJob.perform_later(params[:as_of], current_user.id, portfolio_company_id:)
      redirect_to investor_path(@investor, tab: 'docs-tab'), notice: "Report generation started, please check back in a few mins"
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
                                .query(query_string: { fields: InvestorIndex::SEARCH_FIELDS,
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
        redirect_url = params[:back_to].presence || investor_url(@investor)
        format.turbo_stream do
          @frame = params[:turbo_frame] || params[:investor][:turbo_frame] || "new_deal_investor"
          partial = params[:back_to].presence || "investors/board_form"
          UserAlert.new(user_id: current_user.id, message: "Investor was successfully created!", level: "success").broadcast
          render turbo_stream: [
            turbo_stream.replace(@frame, partial:, locals: { frame: @frame })
          ]
        end
        format.html { redirect_to redirect_url, notice: "Investor was successfully created." }
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
    params.require(:investor).permit(:investor_entity_id, :tag_list, :investor_name, :form_type_id,
                                     :pan, :entity_id, :category, :city, :primary_email, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
