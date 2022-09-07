class ValuationsController < ApplicationController
  before_action :set_valuation, only: %i[show edit update destroy]

  # GET /valuations or /valuations.json
  def index
    @valuations = policy_scope(Valuation).includes(:entity)
    @valuations = @valuations.where(owner_id: params[:owner_id], owner_type: params[:owner_type]) if params[:owner_id].present? && params[:owner_type].present?
  end

  # GET /valuations/1 or /valuations/1.json
  def show; end

  # GET /valuations/new
  def new
    @valuation = Valuation.new(valuation_params)
    @valuation.entity_id = current_user.entity_id
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
    @valuation = Valuation.new(valuation_params)
    @valuation.entity_id = current_user.entity_id
    @valuation.pre_money_valuation_cents = valuation_params[:pre_money_valuation].to_f * 100
    @valuation.per_share_value_cents = valuation_params[:per_share_value].to_f * 100
    authorize @valuation

    respond_to do |format|
      if @valuation.save
        if @valuation.owner
          format.html { redirect_to [@valuation.owner, tab: "valuations-tab"], notice: "Valuation was successfully created." }
        else
          format.html { redirect_to valuation_url(@valuation), notice: "Valuation was successfully created." }
        end
        format.json { render :show, status: :created, location: @valuation }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @valuation.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /valuations/1 or /valuations/1.json
  def update
    respond_to do |format|
      if @valuation.update(valuation_params)
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
      format.html { redirect_to valuations_url, notice: "Valuation was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_valuation
    @valuation = Valuation.find(params[:id])
    authorize @valuation
  end

  # Only allow a list of trusted parameters through.
  def valuation_params
    params.require(:valuation).permit(:entity_id, :valuation_date, :pre_money_valuation,
                                      :owner_id, :owner_type,
                                      :form_type_id, :per_share_value, reports: [], properties: {})
  end
end
