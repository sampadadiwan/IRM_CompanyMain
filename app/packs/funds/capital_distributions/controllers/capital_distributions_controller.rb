class CapitalDistributionsController < ApplicationController
  before_action :set_capital_distribution, only: %i[show edit update destroy approve redeem_units payments_completed]

  # GET /capital_distributions or /capital_distributions.json
  def index
    @q = CapitalDistribution.ransack(params[:q])
    @capital_distributions = policy_scope(@q.result).includes(:fund, :entity)
    @capital_distributions = @capital_distributions.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_distributions = @capital_distributions.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
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
    respond_to do |format|
      if @capital_distribution.save
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
    @capital_distribution.destroy

    respond_to do |format|
      format.html { redirect_to capital_distributions_url, notice: "Capital distribution was successfully destroyed." }
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
    @capital_distribution.capital_distribution_payments.update(completed: true)
    redirect_to capital_distribution_url(@capital_distribution), notice: "All payments marked as completed."
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
    params.require(:capital_distribution).permit(:fund_id, :entity_id, :form_type_id, :cost_of_investment, :reinvestment, :income, :distribution_date, :title, :completed, :capital_commitment_id, :distribution_on, :generate_payments, :completed, :notes, distribution_fees_attributes: %i[id name start_date end_date notes fee_type _destroy], unit_prices: {}, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
