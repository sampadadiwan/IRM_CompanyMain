class ScenarioInvestmentsController < ApplicationController
  before_action :set_scenario_investment, only: %i[show edit update destroy]

  # GET /scenario_investments or /scenario_investments.json
  def index
    authorize PortfolioScenario

    @scenario_investments = policy_scope(ScenarioInvestment).includes(:portfolio_company, :user).order(transaction_date: :desc)

    @scenario_investments = @scenario_investments.where(portfolio_scenario_id: params[:portfolio_scenario_id]) if params[:portfolio_scenario_id].present?
  end

  # GET /scenario_investments/1 or /scenario_investments/1.json
  def show; end

  # GET /scenario_investments/new
  def new
    @scenario_investment = ScenarioInvestment.new(scenario_investment_params)
    @scenario_investment.user_id = current_user.id
    @scenario_investment.entity_id = @scenario_investment.portfolio_scenario.entity_id
    @scenario_investment.fund_id = @scenario_investment.portfolio_scenario.fund_id
    @scenario_investment.transaction_date = Time.zone.today
    authorize @scenario_investment
  end

  # GET /scenario_investments/1/edit
  def edit; end

  # POST /scenario_investments or /scenario_investments.json
  def create
    @scenario_investment = ScenarioInvestment.new(scenario_investment_params)
    @scenario_investment.user_id = current_user.id
    @scenario_investment.entity_id = @scenario_investment.portfolio_scenario.entity_id
    authorize @scenario_investment

    respond_to do |format|
      if @scenario_investment.save
        format.turbo_stream { render :create }
        format.html { redirect_to scenario_investment_url(@scenario_investment), notice: "Scenario investment was successfully created." }
        format.json { render :show, status: :created, location: @scenario_investment }
      else
        format.turbo_stream { render :new }
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @scenario_investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /scenario_investments/1 or /scenario_investments/1.json
  def update
    respond_to do |format|
      if @scenario_investment.update(scenario_investment_params)
        format.html { redirect_to scenario_investment_url(@scenario_investment), notice: "Scenario investment was successfully updated." }
        format.turbo_stream { render :update }
        format.json { render :show, status: :ok, location: @scenario_investment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render :edit }
        format.json { render json: @scenario_investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /scenario_investments/1 or /scenario_investments/1.json
  def destroy
    @scenario_investment.destroy

    respond_to do |format|
      format.html { redirect_to portfolio_scenario_path(@scenario_investment.portfolio_scenario), notice: "Scenario investment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_scenario_investment
    @scenario_investment = ScenarioInvestment.find(params[:id])
    authorize @scenario_investment
  end

  # Only allow a list of trusted parameters through.
  def scenario_investment_params
    params.require(:scenario_investment).permit(:entity_id, :fund_id, :portfolio_scenario_id, :user_id, :transaction_date, :portfolio_company_id, :price, :quantity, :notes, :investment_instrument_id)
  end
end
