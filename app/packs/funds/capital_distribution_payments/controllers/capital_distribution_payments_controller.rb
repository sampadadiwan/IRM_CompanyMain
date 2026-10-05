class CapitalDistributionPaymentsController < ApplicationController
  # Figures a distribution notice prints: changing one makes the payment's notice out of date
  NOTICE_FIGURES = %w[income_cents cost_of_investment_cents reinvestment_cents net_payable_cents payment_date].freeze

  before_action :set_capital_distribution_payment, only: %i[show edit update destroy preview generate_docs payments_completed send_notification]

  # GET /capital_distribution_payments or /capital_distribution_payments.json
  def index
    result = CapitalDistributionPaymentList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = result.q
    @capital_distribution_payments = result.capital_distribution_payments

    @pagy, @capital_distribution_payments = pagy(@capital_distribution_payments, limit: params[:per_page] || 10) if params[:all].blank? && !request.format.xlsx?

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
        # A payment added by hand can complete Create payments (real time; no-op without a journey)
        # Worked examples H2 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
        @capital_distribution_payment.capital_distribution.journey_progress!(actor: current_user)
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
    started_at = Time.current # before the change, so later sign-offs given before it are reset
    @capital_distribution_payment.assign_attributes(capital_distribution_payment_params)
    result = CapitalDistributionPaymentUpdate.call(capital_distribution_payment: @capital_distribution_payment)
    respond_to do |format|
      if result.success?
        journey_undo(started_at, "Payment #{@capital_distribution_payment.folio_id} edited")
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
    # If skip_doc_gen is set to yes in the folio then notice will not be generated for this dist payment
    # skip_doc_gen is used and not skip_dist notice to keep things simple
    if @capital_distribution_payment.capital_commitment.skip_doc_gen?
      redirect_to capital_distribution_payment_path(@capital_distribution_payment), alert: "Notice cannot be generated as skip_doc_gen is set to Yes in the Commitment"
    else
      CapitalDistributionPaymentDocJob.perform_later(@capital_distribution_payment.capital_distribution_id, @capital_distribution_payment.id, current_user.id)
      redirect_to capital_distribution_payment_path(@capital_distribution_payment), notice: "Documentation generation started, please check back in a few mins."
    end
  end

  def send_notification
    # If dist notice generation is skipped then notification should also be skipped
    if @capital_distribution_payment.capital_commitment.skip_doc_gen?
      redirect_to capital_distribution_payment_path(@capital_distribution_payment), alert: "Notification cannot be sent as skip_doc_gen is set to Yes in the Commitment"
    else
      result = CapitalDistributionPaymentSendNotification.call(capital_distribution_payment: @capital_distribution_payment, force_notification: true)
      msg = result[:notification_message]
      # Real-time journey progress (no-op without a journey). Worked examples H7 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
      @capital_distribution_payment.capital_distribution.journey_progress!(actor: current_user)
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
  end

  # DELETE /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def destroy
    started_at = Time.current
    respond_to do |format|
      if @capital_distribution_payment.destroy
        journey_undo(started_at, "Payment #{@capital_distribution_payment.folio_id} deleted")
        format.html { redirect_to capital_distribution_payments_url, notice: "Capital distribution payment was successfully destroyed." }
        format.json { head :no_content }
      else
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), alert: @capital_distribution_payment.errors.full_messages.join(", ") }
        format.json { render json: @capital_distribution_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  def payments_completed
    @capital_distribution_payment.completed = true
    notice = if CapitalDistributionPaymentUpdate.call(capital_distribution_payment: @capital_distribution_payment).success?
               "Capital distribution payment was successfully updated."
             else
               "Capital distribution payment could not be updated. #{@capital_distribution_payment.errors.full_messages.join(', ')}"
             end
    # Real-time journey progress (no-op without a journey). Worked examples H6 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
    @capital_distribution_payment.capital_distribution.journey_progress!(actor: current_user)

    redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: notice
  end

  private

  # A payment was edited (e.g. Completed unticked, figures changed) or deleted: re-check the
  # distribution's journey as an undo, so it moves back and later sign-offs given before the change
  # are reset. Changed figures also invalidate Generate notices — the notices on file show the old
  # figures, and only notices generated afterwards satisfy it again (design Decision 11).
  # Worked examples E9, E10 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def journey_undo(started_at, note)
    distribution = @capital_distribution_payment.capital_distribution
    if @capital_distribution_payment.saved_changes.keys.intersect?(NOTICE_FIGURES)
      # The task passes again only when every notice is newer than this change, so all of them are regenerated
      distribution.journey_invalidate(check_keys: %w[capital_distribution.generate_notices], actor: current_user,
                                      reason: "A payment's figures changed after the notices were generated — unapprove all of this distribution's notices on the Documents screen, then click Generate Documents")
    end
    distribution.journey_undo_evaluate(note:, started_at:, actor: current_user)
  end

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
