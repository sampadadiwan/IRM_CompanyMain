class PortfolioInvestmentsController < ApplicationController
  before_action :set_portfolio_investment, only: %i[show edit update destroy]
  skip_after_action :verify_authorized, only: %i[sub_categories]

  # GET /portfolio_investments or /portfolio_investments.json
  def index
    @portfolio_investments = policy_scope(PortfolioInvestment).includes(:aggregate_portfolio_investment, :capital_commitment, :fund)
    @portfolio_investments = @portfolio_investments.where(fund_id: params[:fund_id]) if params[:fund_id]
    @portfolio_investments = @portfolio_investments.where(aggregate_portfolio_investment_id: params[:aggregate_portfolio_investment_id]) if params[:aggregate_portfolio_investment_id]
  end

  # GET /portfolio_investments/1 or /portfolio_investments/1.json
  def show; end

  # GET /portfolio_investments/new
  def new
    @portfolio_investment = PortfolioInvestment.new(portfolio_investment_params)
    @portfolio_investment.entity_id = @portfolio_investment.fund.entity_id
    @portfolio_investment.investment_date ||= Time.zone.today

    authorize @portfolio_investment

    if @portfolio_investment.portfolio_company
      last_pi = PortfolioInvestment.where(entity_id: @portfolio_investment.entity_id, portfolio_company_id: @portfolio_investment.portfolio_company_id).last
      @portfolio_investment.category = last_pi.category
      @portfolio_investment.sub_category = last_pi.sub_category
      @portfolio_investment.sector = last_pi.sector
      @portfolio_investment.startup = last_pi.startup
      @portfolio_investment.investment_domicile = last_pi.investment_domicile
    end

    setup_custom_fields(@portfolio_investment)
  end

  # GET /portfolio_investments/1/edit
  def edit
    setup_custom_fields(@portfolio_investment)
  end

  # POST /portfolio_investments or /portfolio_investments.json
  def create
    @portfolio_investment = PortfolioInvestment.new(portfolio_investment_params)
    pre_process @portfolio_investment

    respond_to do |format|
      if @portfolio_investment.save
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
    pre_process @portfolio_investment
    respond_to do |format|
      if @portfolio_investment.update(portfolio_investment_params)
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

  def sub_categories
    @sub_categories = PortfolioInvestment::CATEGORIES[params[:category]]
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
                                                 :amount, :quantity, :investment_type, :notes, :form_type_id, :category, :sub_category, :sector, :startup, :investment_domicile,
                                                 :commitment_type, :capital_commitment_id, :folio_id, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
