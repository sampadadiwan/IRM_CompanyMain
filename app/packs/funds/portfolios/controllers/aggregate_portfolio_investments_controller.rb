class AggregatePortfolioInvestmentsController < ApplicationController
  before_action :set_aggregate_portfolio_investment, only: %i[show edit update destroy toggle_show_portfolio]

  # GET /aggregate_portfolio_investments or /aggregate_portfolio_investments.json
  def index
    result = AggregatePortfolioInvestmentList.call(current_user, params) { |relation| policy_scope(relation) }

    @q = result.q
    @aggregate_portfolio_investments = result.aggregate_portfolio_investments
    @time_series = result.time_series
    @fields = result.fields
    @show_fund_name = result.show_fund_name

    @pagy, @aggregate_portfolio_investments = pagy(@aggregate_portfolio_investments, limit: params[:per_page]) if params[:time_series].blank? && params[:all].blank?

    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json
    end
  end

  # GET /aggregate_portfolio_investments/1 or /aggregate_portfolio_investments/1.json
  def show; end

  # GET /aggregate_portfolio_investments/new
  def new
    @aggregate_portfolio_investment = AggregatePortfolioInvestment.new(aggregate_portfolio_investment_params)
    authorize @aggregate_portfolio_investment
  end

  # GET /aggregate_portfolio_investments/1/edit
  def edit; end

  def toggle_show_portfolio
    if @aggregate_portfolio_investment.update(show_portfolio: !@aggregate_portfolio_investment.show_portfolio)
      redirect_to aggregate_portfolio_investment_path(@aggregate_portfolio_investment), notice: "Show portfolio was successfully updated."
    else
      redirect_to aggregate_portfolio_investment_path(@aggregate_portfolio_investment), alert: "Show portfolio was not updated."
    end
  end

  # POST /aggregate_portfolio_investments or /aggregate_portfolio_investments.json
  def create
    @aggregate_portfolio_investment = AggregatePortfolioInvestment.new(aggregate_portfolio_investment_params)
    authorize @aggregate_portfolio_investment

    respond_to do |format|
      if @aggregate_portfolio_investment.save
        format.html { redirect_to aggregate_portfolio_investment_url(@aggregate_portfolio_investment), notice: "Aggregate portfolio investment was successfully created." }
        format.json { render :show, status: :created, location: @aggregate_portfolio_investment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @aggregate_portfolio_investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /aggregate_portfolio_investments/1 or /aggregate_portfolio_investments/1.json
  def update
    respond_to do |format|
      if @aggregate_portfolio_investment.update(aggregate_portfolio_investment_params)
        format.html { redirect_to aggregate_portfolio_investment_url(@aggregate_portfolio_investment), notice: "Aggregate portfolio investment was successfully updated." }
        format.json { render :show, status: :ok, location: @aggregate_portfolio_investment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @aggregate_portfolio_investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /aggregate_portfolio_investments/1 or /aggregate_portfolio_investments/1.json
  def destroy
    @aggregate_portfolio_investment.destroy

    respond_to do |format|
      format.html { redirect_to aggregate_portfolio_investments_url, notice: "Aggregate portfolio investment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_aggregate_portfolio_investment
    @aggregate_portfolio_investment = AggregatePortfolioInvestment.with_snapshots.find(params[:id])
    authorize @aggregate_portfolio_investment

    api = @aggregate_portfolio_investment
    @bread_crumbs = { Funds: funds_path,
                      "#{api.fund.name}": fund_path(api.fund),
                      'Portfolio Investments': fund_path(@aggregate_portfolio_investment.fund, tab: "portfolio-investments-tab"),
                      "#{api}": aggregate_portfolio_investment_path(api) }
  end

  # Only allow a list of trusted parameters through.
  def aggregate_portfolio_investment_params
    params.require(:aggregate_portfolio_investment).permit(:entity_id, :fund_id, :portfolio_company_id, :portfolio_company_type, :quantity, :fmv, :avg_cost, :show_portfolio)
  end
end
