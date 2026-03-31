class RatioFormulasController < ApplicationController
  before_action :set_fund
  before_action :set_ratio_formula, only: %i[show edit update destroy]
  after_action :verify_authorized

  def index
    authorize RatioFormula
    @q = @fund.ratio_formulas.ransack(params[:q])
    @ratio_formulas = policy_scope(@q.result).includes(:fund)
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund), 'Ratio Formulas': nil }
  end

  def show
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund), 'Ratio Formulas': fund_ratio_formulas_path(@fund), 'Ratio Formula Detail': nil }
  end

  def new
    @ratio_formula = @fund.ratio_formulas.new(entity_id: @fund.entity_id)
    authorize @ratio_formula
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund), 'Ratio Formulas': fund_ratio_formulas_path(@fund), 'New Ratio Formula': nil }
  end

  def edit
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund), 'Ratio Formulas': fund_ratio_formulas_path(@fund), 'Edit Ratio Formula': nil }
  end

  def create
    @ratio_formula = @fund.ratio_formulas.new(ratio_formula_params)
    @ratio_formula.entity_id = @fund.entity_id
    authorize @ratio_formula

    if @ratio_formula.save
      redirect_to fund_ratio_formulas_path(@fund), notice: 'Ratio formula was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @ratio_formula.update(ratio_formula_params)
      redirect_to fund_ratio_formulas_path(@fund), notice: 'Ratio formula was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @ratio_formula.destroy
    redirect_to fund_ratio_formulas_path(@fund), notice: 'Ratio formula was successfully destroyed.'
  end

  private

  def set_fund
    @fund = Fund.find(params[:fund_id])
  end

  def set_ratio_formula
    @ratio_formula = @fund.ratio_formulas.find(params[:id])
    authorize @ratio_formula
  end

  def ratio_formula_params
    # Since ratios and account_entry_names are arrays, we need to permit them accordingly
    params.require(:ratio_formula).permit(:level, :action, :period, ratios: [], account_entry_names: [])
  end
end
