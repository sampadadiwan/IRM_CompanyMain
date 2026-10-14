class AggregatePortfolioInvestmentsController < ApplicationController
  # LPs never see the holding page: old links go to the company's LP page, which authorises them (H16, E68, X16)
  before_action :redirect_lp_to_company_page, only: %i[show]
  before_action :set_aggregate_portfolio_investment, only: %i[show edit update destroy]

  # GET /aggregate_portfolio_investments or /aggregate_portfolio_investments.json
  def index
    result = AggregatePortfolioInvestmentList.call(current_user, params) { |relation| policy_scope(relation) }

    @q = result.q
    @aggregate_portfolio_investments = result.aggregate_portfolio_investments
    @time_series = result.time_series
    @fields = result.fields
    @show_fund_name = result.show_fund_name

    @pagy, @aggregate_portfolio_investments = pagy(@aggregate_portfolio_investments, limit: params[:per_page]) if params[:time_series].blank? && params[:all].blank?

    # H3 — an LP on an own-share view gets Your Cost / Your FMV / Your Multiple on each row (nil otherwise, E40)
    @lp_own_share = LpOwnShareSummary.for(current_user, Fund.find_by(id: params[:fund_id])) if params[:fund_id].present?
    @lp_own_share&.annotate(@aggregate_portfolio_investments)
    annotate_lp_company_links if current_user.curr_role_investor? && params[:fund_id].present? && params[:time_series].blank?

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
  # E44 — in an LP's holdings list a company name links to its LP page only when the LP can open it (shared,
  # visible through this fund); otherwise it is plain text
  def annotate_lp_company_links
    fund = Fund.find_by(id: params[:fund_id])
    return unless fund

    visibility = LpPortfolioVisibility.for_user(current_user)
    @lp_company_links = true
    # Annotate the very rows the view renders (a new .includes relation would load different objects)
    rows = @aggregate_portfolio_investments.to_a
    ActiveRecord::Associations::Preloader.new(records: rows, associations: :portfolio_company).call
    rows.each do |api|
      company = api.portfolio_company
      api.lp_company_cell = if company.show_to_lps && visibility.openable?(company, fund)
                              helpers.link_to(api.portfolio_company_name, lp_company_dashboard_path(company, fund_id: fund.id), data: { turbo: false })
                            else
                              api.portfolio_company_name
                            end
    end
  end

  # The retired holding preview page: an LP opening a holding address (with or without ?preview=true) lands on
  # the company's LP Company Dashboard for that fund, which decides access — the preview parameter no longer
  # opens anything (X16). Worked examples H16, E68, X16 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  def redirect_lp_to_company_page
    return unless current_user.curr_role_investor?

    holding = AggregatePortfolioInvestment.find(params[:id])
    skip_authorization
    redirect_to lp_company_dashboard_path(holding.portfolio_company_id, fund_id: holding.fund_id)
  end

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
    params.require(:aggregate_portfolio_investment).permit(:entity_id, :fund_id, :portfolio_company_id, :portfolio_company_type, :quantity, :fmv, :avg_cost)
  end
end
