class InvestmentsController < ApplicationController
  before_action :set_investment, only: %i[show edit update destroy]

  # GET /investments
  def index
    @bread_crumbs = { Investments: investments_path }
    @q = Investment.ransack(params[:q])
    @investments = policy_scope(@q.result).includes(:portfolio_company)
    @investments = filter_params(
      @investments,
      :portfolio_company_id,
      :investment_type,
      :investor_name,
      :category,
      :funding_round,
      :import_upload_id
    )

    if params[:portfolio_company_id].present?
      @portfolio_company_id = params[:portfolio_company_id]
      @portfolio_company = Investor.find(@portfolio_company_id)
      @bread_crumbs[@portfolio_company.investor_name.to_s] = investor_path(@portfolio_company)
      authorize @portfolio_company, :show?
    end

    # We want to disable pagination when using the ag grid or filtering by portfolio company. For portfolio_company specially the cap table grpahs and charts depend on having all investments loaded.
    @use_pagy = params[:ag].blank? && params[:portfolio_company_id].blank?

    @pagy, @investments = pagy(@investments) if @use_pagy

    respond_to do |format|
      format.html
      format.xlsx
    end
  end

  # GET /investments/1
  def show; end

  # GET /investments/new
  def new
    @investment = Investment.new
    @investment.portfolio_company_id = params[:portfolio_company_id] if params[:portfolio_company_id].present?
    @investment.entity_id = current_user.entity_id

    @bread_crumbs = { Investments: investments_path }
    @bread_crumbs[@investment.portfolio_company.investor_name.to_s] = investor_path(@investment.portfolio_company) if @investment.portfolio_company.present?
    @bread_crumbs[:New] = nil

    authorize @investment
  end

  # GET /investments/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
  end

  # POST /investments
  def create
    @investment = Investment.new(investment_params)
    @investment.entity_id = current_user.entity_id
    authorize @investment
    if @investment.save
      redirect_to @investment, notice: "Investment was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /investments/1
  def update
    if @investment.update(investment_params)
      redirect_to @investment, notice: "Investment was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /investments/1
  def destroy
    @investment.destroy!
    redirect_to investments_url, notice: "Investment was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investment
    @investment = Investment.find(params[:id])
    authorize @investment
    @bread_crumbs = { Investments: investments_path }
    @bread_crumbs[@investment.portfolio_company.investor_name.to_s] = investor_path(@investment.portfolio_company) if @investment.portfolio_company.present?
    @bread_crumbs[@investment.to_s] = investment_path(@investment)
  end

  # Only allow a list of trusted parameters through.
  def investment_params
    params.require(:investment).permit(:portfolio_company_id, :category, :investor_name, :investment_type, :funding_round, :quantity, :price, :investment_date, :notes, :currency, :instrument_name, :instrument_quantity, properties: {})
  end
end
