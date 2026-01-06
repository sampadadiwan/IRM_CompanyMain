class CapitalDistributionPaymentsController < ApplicationController
  before_action :set_capital_distribution_payment, only: %i[show edit update destroy preview generate_docs payments_completed send_notification]

  # GET /capital_distribution_payments or /capital_distribution_payments.json
  def index
    result = CapitalDistributionPaymentList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = result.q
    @capital_distribution_payments = result.capital_distribution_payments

    @pagy, @capital_distribution_payments = pagy(@capital_distribution_payments, limit: params[:per_page] || 10) if params[:all].blank? && !request.format.xlsx?
    @report = Report.find_by(id: params[:report_id]) if params[:report_id].present?

    respond_to do |format|
      format.html
      format.xlsx
      format.json { render json: CapitalDistributionPaymentDatatable.new(params, capital_distribution_payments: @capital_distribution_payments) }
    end
  end

  # GET /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def show; end

  # GET /capital_distribution_payments/new
  def new
    @capital_distribution_payment = CapitalDistributionPayment.new(capital_distribution_payment_params)
    @capital_distribution_payment.entity_id = @capital_distribution_payment.capital_distribution.entity_id
    @capital_distribution_payment.fund_id = @capital_distribution_payment.capital_distribution.fund_id
    @capital_distribution_payment.payment_date = Time.zone.today

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
    result = CapitalDistributionPaymentCreate.call(capital_distribution_payment: @capital_distribution_payment)
    respond_to do |format|
      if result.success?
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
    @capital_distribution_payment.assign_attributes(capital_distribution_payment_params)
    result = CapitalDistributionPaymentUpdate.call(capital_distribution_payment: @capital_distribution_payment)
    respond_to do |format|
      if result.success?
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: "Capital distribution payment was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_distribution_payment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_distribution_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # Generated Distribution Notice For all thhe payment
  def generate_docs
    CapitalDistributionPaymentDocJob.perform_later(@capital_distribution_payment.capital_distribution_id, @capital_distribution_payment.id, current_user.id)
    redirect_to capital_distribution_payment_path(@capital_distribution_payment), notice: "Documentation generation started, please check back in a few mins."
  end

  def send_notification
    result = CapitalDistributionPaymentSendNotification.call(capital_distribution_payment: @capital_distribution_payment, force_notification: true)
    msg = result[:notification_message]
    respond_to do |format|
      if result.success?
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: msg }
        format.json { render :show, status: :ok, location: @capital_distribution_payment }
      else
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), alert: "#{msg}. #{@capital_distribution_payment.errors.full_messages.join(', ')}" }
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

  def payments_completed
    @capital_distribution_payment.completed = true
    notice = if CapitalDistributionPaymentUpdate.call(capital_distribution_payment: @capital_distribution_payment).success?
               "Capital distribution payment was successfully updated."
             else
               "Capital distribution payment could not be updated. #{@capital_distribution_payment.errors.full_messages.join(', ')}"
             end

    redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: notice
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_distribution_payment
    @capital_distribution_payment = CapitalDistributionPayment.find(params[:id])
    authorize(@capital_distribution_payment)
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_distribution_payment.fund.name}": fund_path(@capital_distribution_payment.fund),
                      "#{@capital_distribution_payment.capital_distribution}": capital_distribution_path(id: @capital_distribution_payment.capital_distribution_id),
                      "#{@capital_distribution_payment}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_distribution_payment_params
    params.require(:capital_distribution_payment).permit(:fund_id, :entity_id, :capital_distribution_id, :investor_id, :form_type_id, :income, :payment_date, :completed, :folio_id, properties: {})
  end
end
