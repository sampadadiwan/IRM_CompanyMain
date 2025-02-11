class CapitalRemittancePaymentsController < ApplicationController
  before_action :set_capital_remittance_payment, only: %i[show edit update destroy]

  # GET /capital_remittance_payments or /capital_remittance_payments.json
  def index
    @capital_remittance_payments = policy_scope(CapitalRemittancePayment).includes(:entity, capital_remittance: :fund)
    @capital_remittance_payments = @capital_remittance_payments.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
  end

  # GET /capital_remittance_payments/1 or /capital_remittance_payments/1.json
  def show; end

  # GET /capital_remittance_payments/new
  def new
    @capital_remittance_payment = CapitalRemittancePayment.new(capital_remittance_payment_params)
    @capital_remittance_payment.entity_id = @capital_remittance_payment.capital_remittance.entity_id
    @capital_remittance_payment.fund_id = @capital_remittance_payment.capital_remittance.fund_id
    @capital_remittance_payment.payment_date ||= Time.zone.today
    authorize(@capital_remittance_payment)
  end

  # GET /capital_remittance_payments/1/edit
  def edit; end

  # POST /capital_remittance_payments or /capital_remittance_payments.json
  def create
    @capital_remittance_payment = CapitalRemittancePayment.new(capital_remittance_payment_params)
    authorize(@capital_remittance_payment)
    respond_to do |format|
      if @capital_remittance_payment.save
        format.html { redirect_to capital_remittance_payment_url(@capital_remittance_payment), notice: "Capital remittance payment was successfully created." }
        format.json { render :show, status: :created, location: @capital_remittance_payment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_remittance_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_remittance_payments/1 or /capital_remittance_payments/1.json
  def update
    respond_to do |format|
      if @capital_remittance_payment.update(capital_remittance_payment_params)
        format.html { redirect_to capital_remittance_payment_url(@capital_remittance_payment), notice: "Capital remittance payment was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_remittance_payment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_remittance_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_remittance_payments/1 or /capital_remittance_payments/1.json
  def destroy
    @capital_remittance_payment.destroy

    respond_to do |format|
      format.html { redirect_to capital_remittance_url(@capital_remittance_payment.capital_remittance), notice: "Capital remittance payment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_remittance_payment
    @capital_remittance_payment = CapitalRemittancePayment.find(params[:id])
    authorize(@capital_remittance_payment)
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_remittance_payment.fund.name}": fund_path(@capital_remittance_payment.fund),
                      'Capital Call': capital_call_path(id: @capital_remittance_payment.capital_remittance.capital_call_id),
                      "#{@capital_remittance_payment.capital_remittance}": capital_remittance_path(@capital_remittance_payment.capital_remittance),
                      "#{@capital_remittance_payment}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_remittance_payment_params
    params.require(:capital_remittance_payment).permit(:fund_id, :capital_remittance_id, :entity_id, :folio_amount, :payment_date, :notes, :payment_proof, :reference_no)
  end
end
