class CapitalDistributionPaymentsController < ApplicationController
  before_action :set_capital_distribution_payment, only: %i[show edit update destroy]

  # GET /capital_distribution_payments or /capital_distribution_payments.json
  def index
    @capital_distribution_payments = policy_scope(CapitalDistributionPayment).includes(:investor, :entity, :fund, :capital_distribution)
    @capital_distribution_payments = @capital_distribution_payments.where(fund_id: params[:fund_id]) if params[:fund_id].present?

    @capital_distribution_payments = @capital_distribution_payments.where(capital_distribution_id: params[:capital_distribution_id]) if params[:capital_distribution_id].present?

    @capital_distribution_payments = @capital_distribution_payments.page(params[:page]) if params[:all].blank?
  end

  def search
    query = params[:query]

    if query.present?
      if params[:fund_id].present?
        # Search in fund provided user is authorized
        @fund = Fund.find(params[:fund_id])
        authorize(@fund, :show?)
        term = { fund_id: @fund.id }
      elsif params[:capital_distribution_id].present?
        # Search in fund provided user is authorized
        @capital_distribution = CapitalDistribution.find(params[:capital_distribution_id])
        authorize(@capital_distribution, :show?)
        term = { capital_distribution_id: @capital_distribution.id }
      else
        # Search in users entity only
        term = { entity_id: current_user.entity_id }
      end

      @capital_distribution_payments = CapitalDistributionPaymentIndex.filter(term:)
                                                                      .query(query_string: { fields: CapitalDistributionPaymentIndex::SEARCH_FIELDS,
                                                                                             query:, default_operator: 'and' })

      @capital_distribution_payments = @capital_distribution_payments.objects
      render "index"
    else
      redirect_to capital_distribution_payments_path(params.to_enum.to_h)
    end
  end

  # GET /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def show; end

  # GET /capital_distribution_payments/new
  def new
    @capital_distribution_payment = CapitalDistributionPayment.new(capital_distribution_payment_params)
    @capital_distribution_payment.entity_id = @capital_distribution_payment.capital_distribution.entity_id
    @capital_distribution_payment.fund_id = @capital_distribution_payment.capital_distribution.fund_id
    authorize(@capital_distribution_payment)
  end

  # GET /capital_distribution_payments/1/edit
  def edit; end

  # POST /capital_distribution_payments or /capital_distribution_payments.json
  def create
    @capital_distribution_payment = CapitalDistributionPayment.new(capital_distribution_payment_params)
    @capital_distribution_payment.entity_id = @capital_distribution_payment.capital_distribution.entity_id
    @capital_distribution_payment.fund_id = @capital_distribution_payment.capital_distribution.fund_id
    authorize(@capital_distribution_payment)

    respond_to do |format|
      if @capital_distribution_payment.save
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: "Capital distribution payment was successfully created." }
        format.json { render :show, status: :created, location: @capital_distribution_payment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_distribution_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def update
    respond_to do |format|
      if @capital_distribution_payment.update(capital_distribution_payment_params)
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: "Capital distribution payment was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_distribution_payment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_distribution_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def destroy
    @capital_distribution_payment.destroy

    respond_to do |format|
      format.html { redirect_to capital_distribution_payments_url, notice: "Capital distribution payment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_distribution_payment
    @capital_distribution_payment = CapitalDistributionPayment.find(params[:id])
    authorize(@capital_distribution_payment)
  end

  # Only allow a list of trusted parameters through.
  def capital_distribution_payment_params
    params.require(:capital_distribution_payment).permit(:fund_id, :entity_id, :capital_distribution_id, :investor_id, :form_type_id, :amount, :payment_date, :completed, properties: {})
  end
end
