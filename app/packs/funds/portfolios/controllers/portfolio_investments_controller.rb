class PortfolioInvestmentsController < ApplicationController
  before_action :set_portfolio_investment, only: %i[show edit update destroy]

  def fetch_rows
    # Step 1: Start with base query using search (Ransack) and eager loading
    @portfolio_investments = ransack_with_snapshot
                             .joins(:investment_instrument)
                             .includes(:aggregate_portfolio_investment, :fund, :investment_instrument)

    # Step 2: Filter by fund (snapshot-aware)
    if params[:fund_id].present?
      if params[:snapshot].present?
        # If snapshot mode, use snapshot versions of the fund
        snapshot_fund_ids = Fund.with_snapshots.where(orignal_id: params[:fund_id]).pluck(:id)
        @portfolio_investments = @portfolio_investments.where(fund_id: snapshot_fund_ids)
      else
        # Otherwise, use the original fund directly
        @portfolio_investments = @portfolio_investments.where(fund_id: params[:fund_id])
      end
    end

    # Step 3: Apply additional filters based on optional parameters
    @portfolio_investments = filter_params(
      @portfolio_investments,
      :portfolio_company_id,
      :import_upload_id,
      :investment_instrument_id,
      :aggregate_portfolio_investment_id,
      :capital_distribution_id
    )

    # Step 4: Perform any additional search refinements using custom logic
    @portfolio_investments = PortfolioInvestmentSearch.perform(@portfolio_investments, current_user, params)
  end

  # GET /portfolio_investments or /portfolio_investments.json
  def index
    fetch_rows

    template = "index"
    if params[:group_fields].present?
      @data_frame = PortfolioInvestmentDf.new.df(@portfolio_investments, current_user, params)
      @adhoc_json = @data_frame.to_a.to_json
      template = params[:template].presence || "index"
    elsif params[:time_series].present?
      @fields = params[:fields].presence || %i[fmv quantity gain]
      @time_series = PortfolioInvestmentTimeSeries.new(@portfolio_investments, @fields).call
    elsif params[:all].blank? && params[:ag].blank? && !request.format.xlsx?
      @pagy, @portfolio_investments = pagy(@portfolio_investments, limit: params[:per_page])
    end

    respond_to do |format|
      format.html do
        render template
      end

      format.turbo_stream { render partial: 'portfolio_investments/index', locals: { portfolio_investments: @portfolio_investments } }

      format.xlsx { render_xlsx(@portfolio_investments) }

      format.json
    end
  end

  # GET /portfolio_investments/1 or /portfolio_investments/1.json
  def show; end

  # GET /portfolio_investments/new
  def new
    @portfolio_investment = params[:portfolio_investment].present? ? PortfolioInvestment.new(portfolio_investment_params) : PortfolioInvestment.new
    @portfolio_investment.entity_id = current_user.entity_id
    @portfolio_investment.investment_date ||= Time.zone.today

    authorize @portfolio_investment

    if @portfolio_investment.portfolio_company
      last_pi = PortfolioInvestment.where(entity_id: @portfolio_investment.entity_id, portfolio_company_id: @portfolio_investment.portfolio_company_id).last
      @portfolio_investment.investment_instrument = last_pi&.investment_instrument
    end

    setup_custom_fields(@portfolio_investment)
  end

  def base_amount_form
    @portfolio_investment = PortfolioInvestment.new
    @portfolio_investment.entity_id = current_user.entity_id
    @portfolio_investment.fund_id = params[:fund_id]
    @portfolio_investment.investment_instrument_id = params[:investment_instrument_id]
    authorize @portfolio_investment
  end

  # GET /portfolio_investments/1/edit
  def edit
    setup_custom_fields(@portfolio_investment)
  end

  # POST /portfolio_investments or /portfolio_investments.json
  def create
    @portfolio_investment = PortfolioInvestment.new(portfolio_investment_params)
    authorize @portfolio_investment

    respond_to do |format|
      if PortfolioInvestmentCreate.call(portfolio_investment: @portfolio_investment).success?
        format.html { redirect_to portfolio_investment_url(@portfolio_investment), notice: "Portfolio investment was successfully created." }
        format.json { render :show, status: :created, location: @portfolio_investment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @portfolio_investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /portfolio_investments/1 or /portfolio_investments/1.json
  def update
    @portfolio_investment.assign_attributes(portfolio_investment_params)
    respond_to do |format|
      if PortfolioInvestmentUpdate.call(portfolio_investment: @portfolio_investment).success?
        format.html { redirect_to portfolio_investment_url(@portfolio_investment), notice: "Portfolio investment was successfully updated." }
        format.json { render :show, status: :ok, location: @portfolio_investment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @portfolio_investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /portfolio_investments/1 or /portfolio_investments/1.json
  def destroy
    @portfolio_investment.destroy

    respond_to do |format|
      format.html { redirect_to fund_path(@portfolio_investment.fund, tab: "portfolio-investments-tab"), notice: "Portfolio investment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_portfolio_investment
    @portfolio_investment = PortfolioInvestment.with_snapshots.find(params[:id])
    authorize @portfolio_investment

    @bread_crumbs = { Funds: funds_path,
                      "#{@portfolio_investment.fund.name}": fund_path(@portfolio_investment.fund),
                      'Portfolio Investments': fund_path(@portfolio_investment.fund, tab: "portfolio-investments-tab"),
                      Aggregate: aggregate_portfolio_investment_path(@portfolio_investment.aggregate_portfolio_investment_id),
                      "#{@portfolio_investment}": nil }
  end

  # Only allow a list of trusted parameters through.
  def portfolio_investment_params
    params.require(:portfolio_investment).permit(:entity_id, :fund_id, :portfolio_company_id, :investment_date, :ex_expenses_base_amount, :quantity, :notes, :form_type_id, :investment_instrument_id, :capital_commitment_id, :folio_id, excused_folio_ids: [], documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
