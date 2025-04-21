class PortfolioCashflowsController < ApplicationController
  before_action :set_portfolio_cashflow, only: %i[show edit update destroy]

  # GET /portfolio_cashflows or /portfolio_cashflows.json
  def index
    # Step 1: Apply policy scope
    @portfolio_cashflows = policy_scope(PortfolioCashflow)

    # Step 2: Apply filters based on presence of params
    @portfolio_cashflows = filter_params(
      @portfolio_cashflows,
      :aggregate_portfolio_investment_id,
      :portfolio_company_id,
      :import_upload_id
    )
  end

  # GET /portfolio_cashflows/1 or /portfolio_cashflows/1.json
  def show; end

  # GET /portfolio_cashflows/new
  def new
    @portfolio_cashflow = PortfolioCashflow.new(portfolio_cashflow_params)
    @portfolio_cashflow.entity_id = @portfolio_cashflow.aggregate_portfolio_investment.entity_id
    @portfolio_cashflow.fund_id = @portfolio_cashflow.aggregate_portfolio_investment.fund_id
    @portfolio_cashflow.portfolio_company_id = @portfolio_cashflow.aggregate_portfolio_investment.portfolio_company_id
    @portfolio_cashflow.investment_instrument_id = @portfolio_cashflow.aggregate_portfolio_investment.investment_instrument_id
    @portfolio_cashflow.payment_date = Time.zone.today
    authorize @portfolio_cashflow
    setup_custom_fields(@portfolio_cashflow)
  end

  # GET /portfolio_cashflows/1/edit
  def edit
    setup_custom_fields(@portfolio_cashflow)
  end

  # POST /portfolio_cashflows or /portfolio_cashflows.json
  def create
    @portfolio_cashflow = PortfolioCashflow.new(portfolio_cashflow_params)
    authorize @portfolio_cashflow

    respond_to do |format|
      if @portfolio_cashflow.save
        format.html { redirect_to portfolio_cashflow_url(@portfolio_cashflow), notice: "Portfolio cashflow was successfully created." }
        format.json { render :show, status: :created, location: @portfolio_cashflow }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @portfolio_cashflow.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /portfolio_cashflows/1 or /portfolio_cashflows/1.json
  def update
    respond_to do |format|
      if @portfolio_cashflow.update(portfolio_cashflow_params)
        format.html { redirect_to portfolio_cashflow_url(@portfolio_cashflow), notice: "Portfolio cashflow was successfully updated." }
        format.json { render :show, status: :ok, location: @portfolio_cashflow }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @portfolio_cashflow.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /portfolio_cashflows/1 or /portfolio_cashflows/1.json
  def destroy
    @portfolio_cashflow.destroy

    respond_to do |format|
      format.html { redirect_to portfolio_cashflows_url, notice: "Portfolio cashflow was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_portfolio_cashflow
    @portfolio_cashflow = PortfolioCashflow.find(params[:id])
    authorize @portfolio_cashflow
    @bread_crumbs = { "#{@portfolio_cashflow.portfolio_company.name}": investor_path(@portfolio_cashflow.portfolio_company), 'Portfolio Cashflow': portfolio_cashflow_path(@portfolio_cashflow) }
  end

  # Only allow a list of trusted parameters through.
  def portfolio_cashflow_params
    params.require(:portfolio_cashflow).permit(:entity_id, :fund_id, :portfolio_company_id, :aggregate_portfolio_investment_id, :payment_date, :amount, :notes, :tag,
                                               :investment_instrument_id, :form_type_id, properties: {})
  end
end
