class CapitalDistributionsController < ApplicationController
  include WithJourneyPanel # show's journey evaluation and the journey action

  before_action :set_capital_distribution, only: %i[show journey edit update destroy approve redeem_units payments_completed generate_docs send_payment_notifications recompute_fees]

  # GET /capital_distributions or /capital_distributions.json
  def index
    service = CapitalDistributionList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = service.q
    @capital_distributions = service.capital_distributions
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
  # Evaluates the distribution's journey on every view so the step bar is always current (WithJourneyPanel).
  # Worked examples H3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  # UI journey J2.1 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#what-users-see
  def show
    @journey = evaluate_journey(@capital_distribution)
  end

  # GET /capital_distributions/:id/journey — just the journey panel, for the frame a real-time update inserts
  # Worked examples E16, E17, X6 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def journey
    render_journey_panel(@capital_distribution)
  end

  def redeem_units
    FundUnitsJob.perform_later(@capital_distribution.id, "CapitalDistribution", @capital_distribution.title, current_user.id)
    redirect_to capital_distribution_path(@capital_distribution), notice: "Redemption process started, please check back in a few mins."
  end

  # GET /capital_distributions/new
  def new
    @capital_distribution = CapitalDistribution.new(capital_distribution_params)
    @capital_distribution.entity_id = @capital_distribution.fund.entity_id
    @capital_distribution.distribution_date = Time.zone.today
    @bread_crumbs = { Funds: funds_path, "#{@capital_distribution.fund.name}": fund_path(@capital_distribution.fund), New: nil }
    authorize @capital_distribution
    setup_custom_fields(@capital_distribution)
    apply_clone_from(@capital_distribution, params[:clone_from_id], params[:clone_mode]) if params[:clone_from_id].present?
  end

  # GET /capital_distributions/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
  end

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
        # Editing distribution_date after payments already exist re-dates every capital_distribution_payment
        # to match (see docs/modules/funds/call_and_distribution_date_cascade_plan.md) and triggers a fee recompute.
        CapitalDistributionDateChangeJob.perform_later(@capital_distribution.id, current_user.id) if @capital_distribution.saved_change_to_distribution_date?
        format.html { redirect_to capital_distribution_url(@capital_distribution), notice: "Capital distribution was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_distribution }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_distribution.errors, status: :unprocessable_entity }
      end
    end
  end

  # This action is used to generate the documentation for the payments of the capital distribution
  def generate_docs
    CapitalDistributionPaymentDocJob.perform_later(@capital_distribution.id, nil, current_user.id)
    redirect_to capital_distribution_path(@capital_distribution), notice: "Documentation generation started, please check back in a few mins. Each distribution payment will have the customized document attached"
  end

  def send_payment_notifications
    CapitalDistributionPaymentNotificationJob.perform_later(@capital_distribution.id, current_user.id)
    redirect_to capital_distribution_path(@capital_distribution), notice: "Notification sending process started, please check back in a few mins."
  end

  # DELETE /capital_distributions/1 or /capital_distributions/1.json
  def destroy
    respond_to do |format|
      if CapitalDistributionDestroy.call(capital_distribution: @capital_distribution).success?
        format.html { redirect_to fund_url(@capital_distribution.fund), notice: "Capital distribution was successfully destroyed." }
        format.json { head :no_content }
      else
        format.html { redirect_to capital_distribution_url(@capital_distribution), alert: @capital_distribution.errors.full_messages.join(", ") }
        format.json { render json: @capital_distribution.errors, status: :unprocessable_entity }
      end
    end
  end

  def approve
    @capital_distribution.approved = true
    @capital_distribution.approved_by_user = current_user

    respond_to do |format|
      if @capital_distribution.save
        # Real-time journey progress (no-op without a journey).
        # Worked examples H5 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
        @capital_distribution.journey_progress!(actor: current_user)
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
    # In batches: a distribution can have thousands of payments (CLAUDE.md large-table rules)
    payments.find_each do |cdp|
      cdp.completed = true
      count += 1 if CapitalDistributionPaymentUpdate.call(capital_distribution_payment: cdp).success?
    end
    # Real-time journey progress (no-op without a journey). Worked examples H6 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
    @capital_distribution.journey_progress!(actor: current_user)

    redirect_to capital_distribution_url(@capital_distribution), notice: "#{count} payments out of #{payments.count} marked as completed."
  end

  def recompute_fees
    CapitalDistributionPaymentRecomputeFeesJob.perform_later(@capital_distribution.id, current_user.id)
    redirect_to capital_distribution_path(@capital_distribution), notice: "Recomputation of distribution fees started, please check back in a few mins."
  end

  private

  # Pre-fills a new (unsaved) capital distribution from an existing one, for the "Clone"
  # and "Create With Fees" actions on the show page. Nothing is persisted here - the user
  # reviews/edits on the new form and saves via the normal create action. Cross-fund copying
  # is allowed - the caller already authorized `create?` on the target fund (in #new), and
  # `authorize source, :show?` below covers the source fund, so both sides are permission-checked.
  def apply_clone_from(target, source_id, mode)
    source = CapitalDistribution.find(source_id)
    authorize source, :show?

    if mode == "full"
      target.title = "#{source.title} (Copy)"
      target.distribution_on = source.distribution_on
      target.cost_of_investment_cents = source.cost_of_investment_cents
      target.income_cents = source.income_cents
      target.reinvestment_cents = source.reinvestment_cents
      target.unit_prices = source.unit_prices
      target.form_type_id = source.form_type_id
      target.send_notification_on_complete = source.send_notification_on_complete
      target.notes = source.notes
      # Deliberately not copied: completed, approved, approved_by_user_id, generate_payments_paid,
      # distribution_amount_cents, completed_distribution_amount_cents, distribution_date (stays "today") -
      # these are progress/state fields on the source, not setup fields for a fresh draft.
    end

    source.distribution_fees.each do |fee|
      target.distribution_fees.build(fee.attributes.except("id", "capital_distribution_id", "entity_id", "fund_id", "created_at", "updated_at"))
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_distribution
    @capital_distribution = CapitalDistribution.find(params[:id])
    authorize @capital_distribution
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_distribution.fund.name}": fund_path(@capital_distribution.fund),
                      "#{@capital_distribution}": capital_distribution_path(@capital_distribution) }
  end

  # Only allow a list of trusted parameters through.
  def capital_distribution_params
    params.require(:capital_distribution).permit(:fund_id, :entity_id, :form_type_id, :cost_of_investment, :reinvestment, :income, :distribution_date, :title, :completed, :capital_commitment_id, :distribution_on, :generate_payments, :completed, :send_notification_on_complete, :notes, distribution_fees_attributes: %i[id name start_date end_date notes fee_type cumulative parent_type parent_ids entry_type audit_name _destroy], unit_prices: {}, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
