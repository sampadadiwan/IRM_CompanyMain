class CapitalRemittancePaymentsController < ApplicationController
  before_action :set_capital_remittance_payment, only: %i[show edit update destroy preview]

  # GET /capital_remittance_payments or /capital_remittance_payments.json
  def index
    service = CapitalRemittancePaymentList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = service.q
    @capital_remittance_payments = service.capital_remittance_payments
    @report = Report.find_by(id: params[:report_id]) if params[:report_id].present?

    @pagy, @capital_remittance_payments = pagy(@capital_remittance_payments, limit: params[:per_page]) if params[:all].blank?
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
    # F: ask permission before the operation saves the payment and raises the remittance / call / fund totals
    authorize(@capital_remittance_payment)
    result = CapitalRemittancePaymentCreate.call(capital_remittance_payment: @capital_remittance_payment)
    respond_to do |format|
      if result.success?
        journey_progress
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
    @capital_remittance_payment.assign_attributes(capital_remittance_payment_params)
    result = CapitalRemittancePaymentUpdate.call(capital_remittance_payment: @capital_remittance_payment)
    respond_to do |format|
      if result.success?
        journey_progress
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
    result = CapitalRemittancePaymentDestroy.wtf?(capital_remittance_payment: @capital_remittance_payment)

    respond_to do |format|
      if result.success?
        journey_progress
        format.html { redirect_to capital_remittance_url(@capital_remittance_payment.capital_remittance), notice: "Capital remittance payment was successfully destroyed." }
        format.json { head :no_content }
      else
        format.html { redirect_to capital_remittance_payment_url(@capital_remittance_payment), alert: @capital_remittance_payment.errors.full_messages.join(", ") }
        # X14: Result has no #error_message (that raised, so a refused delete was a 500); answer with the
        # record's errors like every other 422
        format.json { render json: @capital_remittance_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # Real-time journey progress (no-op without a journey). Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def journey_progress
    @capital_remittance_payment.capital_remittance&.capital_call&.journey_progress!(actor: current_user)
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
    params.require(:capital_remittance_payment).permit(:fund_id, :capital_remittance_id, :entity_id, :folio_amount, :payment_date, :notes, :payment_proof, :reference_no, :payment_notification_sent)
  end
end
