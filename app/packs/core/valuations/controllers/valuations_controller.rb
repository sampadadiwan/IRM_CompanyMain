class ValuationsController < ApplicationController
  before_action :set_valuation, only: %i[show edit update destroy]
  skip_after_action :verify_policy_scoped, only: :index
  after_action :verify_authorized, except: %i[index search bulk_actions value_bridge]

  # GET /valuations or /valuations.json
  def index
    if params[:owner_id].present? && params[:owner_type].present?
      # Ensure user is authorized to see the owner
      owner = Object.const_get(params[:owner_type]).send(:find, params[:owner_id])
      authorize(owner, :show?)
      @valuations = owner.valuations
    else
      @valuations = policy_scope(Valuation)
    end

    @valuations = @valuations.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @valuations = @valuations.includes(:entity, :investment_instrument)
  end

  # GET /valuations/1 or /valuations/1.json
  def show; end

  # GET /valuations/new
  def new
    @valuation = Valuation.new(valuation_params)
    @valuation.entity_id = @valuation.owner&.entity_id || current_user.entity_id
    @valuation.valuation_date = Time.zone.today
    authorize @valuation
    setup_custom_fields(@valuation)
  end

  # GET /valuations/1/edit
  def edit
    setup_custom_fields(@valuation)
  end

  # POST /valuations or /valuations.json
  def create
    valuations = []
    saved_all = true
    # We need to create a valuation for each investment instrument
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

    respond_to do |format|
      if @valuation.update(cleaned_params)
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

    respond_to do |format|
      format.html do
        redirect_to @valuation.owner || valuations_url, notice: "Valuation was successfully destroyed."
      end
      format.json { head :no_content }
    end
  end

  def value_bridge
    if params[:initial_valuation_id].present? && params[:final_valuation_id].present?
      @initial_valuation = Valuation.find(params[:initial_valuation_id])
      authorize(@initial_valuation)
      @final_valuation = Valuation.find(params[:final_valuation_id])
      authorize(@final_valuation)
      @bridge = ValueBridgeService.new(@initial_valuation, @final_valuation).compute_bridge
      render "value_bridge"
    elsif params[:portfolio_company_id].present?
      @portfolio_company = Investor.find(params[:portfolio_company_id])
      authorize(@portfolio_company, :show?)
      render "value_bridge_form"
    else
      redirect_to root_path, alert: "Portfolio company nor specified"
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_valuation
    @valuation = Valuation.find(params[:id])
    authorize @valuation
    @bread_crumbs = { Stakeholders: investors_path(entity_id: @valuation.entity_id), "#{@valuation.owner&.investor_name}": investor_path(@valuation.owner), Valuation: valuation_path(@valuation) }
  end

  # Only allow a list of trusted parameters through.
  def valuation_params
    params.require(:valuation).permit(:entity_id, :valuation_date, :investment_instrument_id, :owner_id, :owner_type, :form_type_id, :per_share_value, :report, :valuation, properties: {})
  end
end
