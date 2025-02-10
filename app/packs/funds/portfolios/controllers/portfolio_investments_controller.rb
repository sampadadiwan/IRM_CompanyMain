class PortfolioInvestmentsController < ApplicationController
  before_action :set_portfolio_investment, only: %i[show edit update destroy]

  # GET /portfolio_investments or /portfolio_investments.json
  def index
    @q = PortfolioInvestment.ransack(params[:q])
    @portfolio_investments = policy_scope(@q.result).joins(:investment_instrument).includes(:aggregate_portfolio_investment, :capital_commitment, :fund, :investment_instrument)
    @portfolio_investments = @portfolio_investments.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @portfolio_investments = @portfolio_investments.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @portfolio_investments = @portfolio_investments.where(investment_instrument_id: params[:investment_instrument_id]) if params[:investment_instrument_id].present?
    @portfolio_investments = @portfolio_investments.where(aggregate_portfolio_investment_id: params[:aggregate_portfolio_investment_id]) if params[:aggregate_portfolio_investment_id]
    @portfolio_investments = PortfolioInvestmentSearch.perform(@portfolio_investments, current_user, params)

    template = "index"
    if params[:group_fields].present?
      @data_frame = PortfolioInvestmentDf.new.df(@portfolio_investments, current_user, params)
      @adhoc_json = @data_frame.to_a.to_json
      template = params[:template].presence || "index"
    elsif params[:all].blank? && params[:ag].blank?
      @portfolio_investments = @portfolio_investments.page(params[:page])
      @portfolio_investments = @portfolio_investments.per(params[:per_page].to_i) if params[:per_page].present?
    end

    respond_to do |format|
      format.html do
        render template
      end
      format.turbo_stream { render partial: 'portfolio_investments/index', locals: { portfolio_investments: @portfolio_investments } }
      format.xlsx
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
      if PortfolioInvestmentCreate.wtf?(portfolio_investment: @portfolio_investment).success?
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
      if PortfolioInvestmentUpdate.wtf?(portfolio_investment: @portfolio_investment).success?
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
    @portfolio_investment = PortfolioInvestment.find(params[:id])
    authorize @portfolio_investment

    @bread_crumbs = { Funds: funds_path,
                      "#{@portfolio_investment.fund.name}": fund_path(@portfolio_investment.fund),
                      'Portfolio Investments': fund_path(@portfolio_investment.fund, tab: "portfolio-investments-tab"),
                      Aggregate: aggregate_portfolio_investment_path(@portfolio_investment.aggregate_portfolio_investment_id),
                      "#{@portfolio_investment}": nil }
  end

  # Only allow a list of trusted parameters through.
  def portfolio_investment_params
    params.require(:portfolio_investment).permit(:entity_id, :fund_id, :portfolio_company_id, :investment_date,
                                                 :ex_expenses_base_amount, :quantity, :notes, :form_type_id, :investment_instrument_id, :capital_commitment_id, :folio_id, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
