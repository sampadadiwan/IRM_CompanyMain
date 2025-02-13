class ExcusedInvestorsController < ApplicationController
  before_action :set_excused_investor, only: %i[show edit update destroy]

  # GET /excused_investors
  def index
    @q = ExcusedInvestor.ransack(params[:q])
    @excused_investors = policy_scope(@q.result).includes(:portfolio_company, :aggregate_portfolio_investment, :portfolio_investment, :capital_commitment)
    @excused_investors = @excused_investors.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?
    @excused_investors = @excused_investors.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @excused_investors = @excused_investors.page(params[:page])
  end

  # GET /excused_investors/1
  def show; end

  # GET /excused_investors/new
  def new
    @excused_investor = ExcusedInvestor.new
    @excused_investor.capital_commitment_id = params[:capital_commitment_id]
    @excused_investor.entity_id = @excused_investor.capital_commitment.entity_id
    @excused_investor.fund_id = @excused_investor.capital_commitment.fund_id

    authorize @excused_investor
  end

  # GET /excused_investors/1/edit
  def edit; end

  # POST /excused_investors
  def create
    @excused_investor = ExcusedInvestor.new(excused_investor_params)
    authorize @excused_investor
    if @excused_investor.save
      redirect_to @excused_investor, notice: "Excused investor was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /excused_investors/1
  def update
    if @excused_investor.update(excused_investor_params)
      redirect_to @excused_investor, notice: "Excused investor was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /excused_investors/1
  def destroy
    @excused_investor.destroy!
    redirect_to excused_investors_url, notice: "Excused investor was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_excused_investor
    @excused_investor = ExcusedInvestor.find(params[:id])
    authorize @excused_investor
  end

  # Only allow a list of trusted parameters through.
  def excused_investor_params
    params.require(:excused_investor).permit(:entity_id, :fund_id, :capital_commitment_id, :portfolio_company_id, :aggregate_portfolio_investment_id, :portfolio_investment_id, :notes)
  end
end
