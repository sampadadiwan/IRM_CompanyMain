class InvestmentsController < ApplicationController
  before_action :set_investment, only: %i[show edit update destroy]

  # GET /investments
  def index
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
    authorize @investment
  end

  # GET /investments/1/edit
  def edit; end

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
  end

  # Only allow a list of trusted parameters through.
  def investment_params
    params.require(:investment).permit(:portfolio_company_id, :category, :investor_name, :investment_type, :funding_round, :quantity, :price, :investment_date, :notes, :currency, properties: {})
  end
end
