class CapitalDistributionPaymentsController < ApplicationController
  before_action :set_capital_distribution_payment, only: %i[show edit update destroy]

  # GET /capital_distribution_payments or /capital_distribution_payments.json
  def index
    @capital_distribution_payments = policy_scope(CapitalDistributionPayment).includes(:investor, :entity)
    @capital_distribution_payments = @capital_distribution_payments.where(fund_id: params[:fund_id]) if params[:fund_id].present?
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
