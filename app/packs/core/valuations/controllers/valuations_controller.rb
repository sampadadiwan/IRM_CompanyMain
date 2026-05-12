class ValuationsController < ApplicationController
  helper ValuationsHelper
  before_action :set_valuation, only: %i[show edit update destroy]
  skip_after_action :verify_policy_scoped, only: :index
  after_action :verify_authorized, except: %i[index search bulk_actions value_bridge analytics]

  # Runs blocker rules server-side before create/update.
  # If blockers fire and the user has not confirmed (force_save != "1"),
  # the save is halted and an error is returned.
  # Warnings are enforced only on the client side (Stimulus modal).
  before_action :enforce_blocker_rules, only: %i[create update]

  # GET /valuations or /valuations.json
  def index
    @bread_crumbs = { Valuations: valuations_path }
    service = ValuationList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = service.q
    @valuations = service.valuations

    per_page = params[:per_page].to_i.nonzero? || 10
    @pagy, @valuations = pagy(@valuations, limit: per_page) if params[:all].blank?

    authorize(service.owner, :show?) if service.owner
  end

  def analytics
    service = ValuationList.call(current_user, params) { |relation| policy_scope(relation) }
    @valuations = service.valuations
    @owner = service.owner
    authorize(@owner, :show?) if @owner
    render "analytics_content", layout: false
  end

  # GET /valuations/1 or /valuations/1.json
  def show; end

  # GET /valuations/new
  def new
    @valuation = Valuation.new(valuation_params)
    @valuation.entity_id = @valuation.owner&.entity_id || current_user.entity_id
    @valuation.valuation_date = Time.zone.today

    @bread_crumbs = { Stakeholders: investors_path(entity_id: @valuation.entity_id) }
    @bread_crumbs["#{@valuation.owner&.investor_name}"] = investor_path(@valuation.owner) if @valuation.owner.present?
    @bread_crumbs[:New] = nil

    authorize @valuation
    setup_custom_fields(@valuation)
  end


  # GET /valuations/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    setup_custom_fields(@valuation)
  end

  def create_vals
    valuations = []
    saved_all = true
    # We need to create a valuation for each investment instrument
    if request.format.html?

      # enforce_blocker_rules before_action already confirmed no blockers — skip the
      # model-level re-evaluation to avoid running the rule engine twice per save.
      WithValidationRules.skip do
        Valuation.transaction do
          params[:investment_instrument_ids].each do |investment_instrument_id|
            next if investment_instrument_id.blank?

            @valuation = Valuation.new(valuation_params)
            @valuation.investment_instrument_id = investment_instrument_id
            @valuation.entity_id = @valuation.owner&.entity_id || current_user.entity_id
            @valuation.per_share_value_cents = valuation_params[:per_share_value].to_d * 100
            authorize @valuation
            saved_all &&= @valuation.save
            valuations << @valuation
            break unless saved_all
          end
        end
      end

    elsif request.format.json?
      WithValidationRules.skip do
        Valuation.transaction do
          @valuation = Valuation.new(valuation_params)
          @valuation.entity_id = @valuation.owner&.entity_id || current_user.entity_id
          @valuation.per_share_value_cents = valuation_params[:per_share_value].to_d * 100
          authorize @valuation
          saved_all = @valuation.save
          valuations << @valuation
        end
      end
    end

    [valuations, saved_all]
  end

  # POST /valuations or /valuations.json
  def create
    # We need to create a valuation for each investment instrument
    _, saved_all = create_vals

    respond_to do |format|
      if saved_all
        notice = "Valuation was successfully created."
        if @valuation.owner_type == "Entity"
          format.html { redirect_to valuation_url(@valuation), notice: }
        else
          format.html { redirect_to [@valuation.owner, { tab: "valuations-tab" }], notice: }
        end
        format.json { render :show, status: :created, location: @valuation }
      else
        format.html { render :new, status: :unprocessable_entity, alert: "Valuation could not be saved. #{@valuation.errors.full_messages}" }
        format.json { render json: @valuation.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /valuations/1 or /valuations/1.json
  def update
    @valuation.per_share_value_cents = valuation_params[:per_share_value].to_d * 100
    # We need to remove the per_share_value from the params hash, this is so the per_share_value_cents is used to update the DB till the last 8 decimal digits. Otherwise only 2 digits gets saved
    cleaned_params = valuation_params.except(:per_share_value)

    # enforce_blocker_rules before_action already confirmed no blockers — skip the
    # model-level re-evaluation to avoid running the rule engine twice per save.
    respond_to do |format|
      if WithValidationRules.skip { @valuation.update(cleaned_params) }
        format.html { redirect_to valuation_url(@valuation), notice: "Valuation was successfully updated." }
        format.json { render :show, status: :ok, location: @valuation }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @valuation.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /valuations/1 or /valuations/1.json
  def destroy
    @valuation.destroy
    if @valuation.deleted? || @valuation.destroyed?
      UpdatePortfolioInvestmentsJob.perform_later(@valuation.investment_instrument.portfolio_investment_ids) if @valuation.investment_instrument.present?

      respond_to do |format|
        format.html do
          redirect_to @valuation.owner || valuations_url, notice: "Valuation was successfully destroyed."
        end
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to @valuation, notice: "Valuation could not be destroyed. #{@valuation.errors.full_messages.join(', ')}"
        end
        format.json { render json: @valuation.errors, status: :unprocessable_entity }
      end
    end
  end

  def value_bridge
    if params[:initial_valuation_id].present? && params[:final_valuation_id].present?
      @initial_valuation = Valuation.with_synthetic.find(params[:initial_valuation_id])
      authorize(@initial_valuation)
      @final_valuation = Valuation.with_synthetic.find(params[:final_valuation_id])
      authorize(@final_valuation)

      @portfolio_company = Investor.find(params[:portfolio_company_id])

      if @initial_valuation.investment_instrument_id == @final_valuation.investment_instrument_id
        @valuation_currency = @initial_valuation.currency
        # Get the value bridge fields from the entity setting if they exist
        @value_bridge_fields = @current_user.entity.entity_setting.value_bridge_cols
        @value_bridge_fields = @value_bridge_fields.split(",").map(&:strip) if @value_bridge_fields
        @moic = params[:moic] == "1"

        @value_bridge_service = ValueBridgeService.new(@initial_valuation, @final_valuation, value_bridge_fields: @value_bridge_fields, moic: @moic)
        @bridge = @value_bridge_service.compute_bridge
      else
        @bridge = nil
      end

      @valuations = if @initial_valuation.form_custom_fields.pluck(:name).include?(Valuation::COMPUTE_VAL_BRIDGE_CF)
                      @portfolio_company.valuations.with_synthetic.search_custom_fields(Valuation::COMPUTE_VAL_BRIDGE_CF, "1").order(valuation_date: :desc)
                    else

                      @portfolio_company.valuations.with_synthetic.order(valuation_date: :desc)
                    end

      render "value_bridge"
    elsif params[:portfolio_company_id].present?
      @portfolio_company = Investor.find(params[:portfolio_company_id])
      authorize(@portfolio_company, :show?)
      @valuations = @portfolio_company.valuations.with_synthetic.order(valuation_date: :desc)

      render "value_bridge_form"
    else
      redirect_to root_path, alert: "Portfolio company nor specified"
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_valuation
    @valuation = Valuation.with_synthetic.find(params[:id])
    authorize @valuation
    @bread_crumbs = { Stakeholders: investors_path(entity_id: @valuation.entity_id) }
    @bread_crumbs["#{@valuation.owner&.investor_name}"] = investor_path(@valuation.owner) if @valuation.owner.present?
    @bread_crumbs["#{@valuation}"] = valuation_path(@valuation)
  end

  # Only allow a list of trusted parameters through.
  def valuation_params
    params.require(:valuation).permit(:entity_id, :valuation_date, :investment_instrument_id, :owner_id, :owner_type, :form_type_id, :per_share_value, :report, :valuation, :synthetic, properties: {})
  end

  # Builds a temporary (unsaved) Valuation from the current params and runs all
  # rules against it.  Blocker rules are enforced regardless of force_save.
  # Warning rules are skipped here — they're handled client-side by the Stimulus modal.
  def enforce_blocker_rules
    # Build the record exactly as the save action would, without persisting it
    temp_record = if action_name == "create"
                    r = Valuation.new(valuation_params)
                    r.entity_id = r.owner&.entity_id || current_user.entity_id
                    r
                  else
                    # dup produces an unpersisted copy (id=nil, persisted?=false).
                    # Context providers guard against self-comparison via `persisted?`,
                    # and valuation_date scoping still excludes the current record correctly.
                    @valuation.dup.tap { |r| r.assign_attributes(valuation_params) }
                  end

    results  = ValidationRuleEvaluator.call(record: temp_record, entity: current_user.entity)
    blockers = results.select(&:blocker?)
    return if blockers.empty?

    # Blockers always prevent saving — force_save does not bypass them
    messages = blockers.map(&:message).join("; ")

    respond_to do |format|
      format.html do
        flash[:alert] = "Cannot save: #{messages}"
        action_name == "create" ? render(:new, status: :unprocessable_entity) : render(:edit, status: :unprocessable_entity)
      end
      format.json { render json: { errors: blockers.map(&:message) }, status: :unprocessable_entity }
    end
  end
end
