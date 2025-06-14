class CapitalDistributionsController < ApplicationController
  before_action :set_capital_distribution, only: %i[show edit update destroy approve redeem_units payments_completed]

  # GET /capital_distributions or /capital_distributions.json
  def index
    @q = CapitalDistribution.ransack(params[:q])
    @capital_distributions = policy_scope(@q.result).includes(:fund, :entity)
    @capital_distributions = @capital_distributions.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_distributions = @capital_distributions.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
  end

  # This action is used only to update the form for CD with dynamic Income (Gain from PIs) and Face Value For Redemption (Cost of PIs), and is triggered when a user selected a PI to be included in the distribution
  def add_pis_to_capital_distribution
    @capital_distribution = CapitalDistribution.new(fund_id: params[:fund_id], entity_id: params[:entity_id])
    authorize @capital_distribution

    @capital_distribution.income_cents = 0
    @capital_distribution.cost_of_investment_cents = 0

    @capital_distribution.fund.portfolio_investments.sells.where(id: params[:portfolio_investment_ids].split(",")).find_each do |pi|
      @capital_distribution.income_cents += pi.gain_cents
      @capital_distribution.cost_of_investment_cents += pi.amount_cents
    end
  end

  # GET /capital_distributions/1 or /capital_distributions/1.json
  def show; end

  def redeem_units
    FundUnitsJob.perform_later(@capital_distribution.id, "CapitalDistribution", @capital_distribution.title, current_user.id)
    redirect_to capital_distribution_path(@capital_distribution), notice: "Redemption process started, please check back in a few mins."
  end

  # GET /capital_distributions/new
  def new
    @capital_distribution = CapitalDistribution.new(capital_distribution_params)
    @capital_distribution.entity_id = @capital_distribution.fund.entity_id
    @capital_distribution.distribution_date = Time.zone.today
    authorize @capital_distribution
  end

  # GET /capital_distributions/1/edit
  def edit; end

  # POST /capital_distributions or /capital_distributions.json
  def create
    @capital_distribution = CapitalDistribution.new(capital_distribution_params)
    authorize @capital_distribution
    result = CapitalDistributionCreate.call(capital_distribution: @capital_distribution, portfolio_investment_ids: params[:portfolio_investment_ids])
    respond_to do |format|
      if result.success?
        format.html { redirect_to capital_distribution_url(@capital_distribution), notice: "Capital distribution was successfully created." }
        format.json { render :show, status: :created, location: @capital_distribution }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_distribution.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_distributions/1 or /capital_distributions/1.json
  def update
    respond_to do |format|
      if @capital_distribution.update(capital_distribution_params)
        format.html { redirect_to capital_distribution_url(@capital_distribution), notice: "Capital distribution was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_distribution }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_distribution.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_distributions/1 or /capital_distributions/1.json
  def destroy
    CapitalDistributionDestroy.call(capital_distribution: @capital_distribution)

    respond_to do |format|
      format.html { redirect_to fund_url(@capital_distribution.fund), notice: "Capital distribution was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def approve
    @capital_distribution.approved = true
    @capital_distribution.approved_by_user = current_user

    respond_to do |format|
      if @capital_distribution.save
        format.html { redirect_to capital_distribution_url(@capital_distribution), notice: "Capital distribution was successfully approved." }
        format.json { render :show, status: :created, location: @capital_distribution }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_distribution.errors, status: :unprocessable_entity }
      end
    end
  end

  def payments_completed
    payments = @capital_distribution.capital_distribution_payments
    count = 0
    payments.each do |cdp|
      cdp.completed = true
      count += 1 if CapitalDistributionPaymentUpdate.call(capital_distribution_payment: cdp).success?
    end

    redirect_to capital_distribution_url(@capital_distribution), notice: "#{count} payments out of #{payments.count} marked as completed."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_distribution
    @capital_distribution = CapitalDistribution.find(params[:id])
    authorize @capital_distribution
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_distribution.fund.name}": fund_path(@capital_distribution.fund),
                      "#{@capital_distribution}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_distribution_params
    params.require(:capital_distribution).permit(:fund_id, :entity_id, :form_type_id, :cost_of_investment, :reinvestment, :income, :distribution_date, :title, :completed, :capital_commitment_id, :distribution_on, :generate_payments, :completed, :send_notification_on_complete, :notes, distribution_fees_attributes: %i[id name start_date end_date notes fee_type _destroy], unit_prices: {}, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
