class PortfolioScenariosController < ApplicationController
  before_action :set_portfolio_scenario, only: %i[show edit update destroy run finalize]
  before_action :preload_scenario_investments, only: %i[show]
  after_action :verify_authorized, except: %i[index], unless: :devise_controller?

  # GET /portfolio_scenarios or /portfolio_scenarios.json
  def index
    authorize PortfolioScenario
    @portfolio_scenarios = policy_scope(PortfolioScenario).includes(:fund, :user).order(created_at: :desc)
    @portfolio_scenarios = @portfolio_scenarios.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @portfolio_scenarios = @portfolio_scenarios.where(user_id: params[:user_id]) if params[:user_id].present?
  end

  # H8: the "Summary Scenario" what-if computes the fund's and every portfolio company's IRR. It was
  # unauthorized (and exempt from verify_authorized), so anyone signed in could read any fund's IRRs
  # by id. Now: a fund this user can see (another firm's is "Access Denied"), and update rights on it
  # - the same test that shows the Portfolio tab's Scenarios button.
  # Tests H8-1, H8-2, H8-3, H8-H — features/security/portfolio_scenario_isolation.feature
  def simple_scenario
    # Only funds in the user's scope resolve
    @fund = policy_scope(Fund).find(params[:fund_id])
    # Read-only employees and LPs can see the fund but not run its what-if
    authorize @fund, :update?
  end

  # GET /portfolio_scenarios/1 or /portfolio_scenarios/1.json
  def show; end

  # GET /portfolio_scenarios/new
  def new
    @portfolio_scenario = PortfolioScenario.new
    @portfolio_scenario.entity_id = current_user.entity_id
    authorize @portfolio_scenario
  end

  # GET /portfolio_scenarios/1/edit
  def edit; end

  # POST /portfolio_scenarios or /portfolio_scenarios.json
  def create
    @portfolio_scenario = PortfolioScenario.new(portfolio_scenario_params)
    @portfolio_scenario.entity_id = current_user.entity_id
    @portfolio_scenario.user_id = current_user.id
    authorize @portfolio_scenario
    respond_to do |format|
      if @portfolio_scenario.save
        format.html { redirect_to portfolio_scenario_url(@portfolio_scenario), notice: "Portfolio scenario was successfully created." }
        format.json { render :show, status: :created, location: @portfolio_scenario }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @portfolio_scenario.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /portfolio_scenarios/1 or /portfolio_scenarios/1.json
  def update
    respond_to do |format|
      if @portfolio_scenario.update(portfolio_scenario_params)
        format.html { redirect_to portfolio_scenario_url(@portfolio_scenario), notice: "Portfolio scenario was successfully updated." }
        format.json { render :show, status: :ok, location: @portfolio_scenario }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @portfolio_scenario.errors, status: :unprocessable_entity }
      end
    end
  end

  def finalize
    if Rails.env.test?
      FinalizePortfolioScenarioJob.perform_now(@portfolio_scenario.id, current_user.id)
    else
      FinalizePortfolioScenarioJob.set(wait: 2.seconds).perform_later(@portfolio_scenario.id, current_user.id)
    end

    redirect_to portfolio_scenario_path(@portfolio_scenario),
                notice: "Finalization enqueued for #{@portfolio_scenario.name}."
  end

  # DELETE /portfolio_scenarios/1 or /portfolio_scenarios/1.json
  def destroy
    @portfolio_scenario.destroy

    respond_to do |format|
      format.html { redirect_to portfolio_scenarios_url, notice: "Portfolio scenario was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def run
    cashflows_currency = params[:cashflows_currency] || "default"
    if Rails.env.test?
      PortfolioScenarioJob.perform_now(@portfolio_scenario.id, current_user.id, return_cash_flows: params[:return_cash_flows], cashflows_currency: cashflows_currency)
    else
      PortfolioScenarioJob.set(wait: 2.seconds).perform_later(@portfolio_scenario.id, current_user.id, return_cash_flows: params[:return_cash_flows], cashflows_currency: cashflows_currency)
    end
    redirect_to portfolio_scenario_url(@portfolio_scenario), notice: "Portfolio scenario is running."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_portfolio_scenario
    @portfolio_scenario = PortfolioScenario.find(params[:id])
    authorize @portfolio_scenario
  end

  def preload_scenario_investments
    ActiveRecord::Associations::Preloader.new(
      records: [@portfolio_scenario],
      associations: { scenario_investments: %i[fund portfolio_company user] }
    ).call
  end

  # Only allow a list of trusted parameters through.
  def portfolio_scenario_params
    params.require(:portfolio_scenario).permit(:entity_id, :fund_id, :name, :user_id)
  end
end
