class InvestmentOpportunitiesController < ApplicationController
  before_action :set_investment_opportunity, only: %i[show edit update destroy]

  # GET /investment_opportunities or /investment_opportunities.json
  def index
    @investment_opportunities = policy_scope(InvestmentOpportunity)
  end

  # GET /investment_opportunities/1 or /investment_opportunities/1.json
  def show; end

  # GET /investment_opportunities/new
  def new
    @investment_opportunity = InvestmentOpportunity.new
    @investment_opportunity.entity_id = current_user.entity_id
    @investment_opportunity.currency = current_user.entity.currency
    @investment_opportunity.last_date = Time.zone.today + 1.month
    authorize @investment_opportunity
  end

  # GET /investment_opportunities/1/edit
  def edit; end

  # POST /investment_opportunities or /investment_opportunities.json
  def create
    @investment_opportunity = InvestmentOpportunity.new(investment_opportunity_params)
    @investment_opportunity.entity_id = current_user.entity_id
    authorize @investment_opportunity

    respond_to do |format|
      if @investment_opportunity.save
        format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Investment opportunity was successfully created." }
        format.json { render :show, status: :created, location: @investment_opportunity }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investment_opportunity.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investment_opportunities/1 or /investment_opportunities/1.json
  def update
    respond_to do |format|
      if @investment_opportunity.update(investment_opportunity_params)
        format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Investment opportunity was successfully updated." }
        format.json { render :show, status: :ok, location: @investment_opportunity }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investment_opportunity.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investment_opportunities/1 or /investment_opportunities/1.json
  def destroy
    @investment_opportunity.destroy

    respond_to do |format|
      format.html { redirect_to investment_opportunities_url, notice: "Investment opportunity was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investment_opportunity
    @investment_opportunity = InvestmentOpportunity.find(params[:id])
    authorize @investment_opportunity
  end

  # Only allow a list of trusted parameters through.
  def investment_opportunity_params
    params.require(:investment_opportunity).permit(:entity_id, :company_name, :fund_raise_amount, :valuation, :min_ticket_size, :last_date, :currency, :logo, :video)
  end
end
