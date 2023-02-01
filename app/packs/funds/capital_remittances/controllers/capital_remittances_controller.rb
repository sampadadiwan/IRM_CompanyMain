class CapitalRemittancesController < ApplicationController
  before_action :set_capital_remittance, only: %i[show edit update destroy verify generate_docs allocate_units]

  # GET /capital_remittances or /capital_remittances.json
  def index
    @capital_remittances = policy_scope(CapitalRemittance).includes(:fund, :capital_call, :entity, capital_commitment: :fund)
    @capital_remittances = @capital_remittances.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_remittances = @capital_remittances.where(status: params[:status]) if params[:status].present?
    @capital_remittances = @capital_remittances.where(verified: params[:verified] == "true") if params[:verified].present?
    @capital_remittances = @capital_remittances.where(capital_call_id: params[:capital_call_id]) if params[:capital_call_id].present?
    @capital_remittances = @capital_remittances.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?

    @capital_remittances = @capital_remittances.page(params[:page]) if params[:all].blank?

    respond_to do |format|
      format.html
      format.xlsx
      format.json { render json: CapitalRemittanceDatatable.new(params, capital_remittances: @capital_remittances) }
    end
  end

  def search
    query = params[:query]

    if query.present?
      if params[:fund_id].present?
        # Search in fund provided user is authorized
        @fund = Fund.find(params[:fund_id])
        authorize(@fund, :show?)
        term = { fund_id: @fund.id }
      elsif params[:capital_call_id].present?
        # Search in fund provided user is authorized
        @capital_call = CapitalCall.find(params[:capital_call_id])
        authorize(@capital_call, :show?)
        term = { capital_call_id: @capital_call.id }
      else
        # Search in users entity only
        term = { entity_id: current_user.entity_id }
      end

      @capital_remittances = CapitalRemittanceIndex.filter(term:)
                                                   .query(query_string: { fields: CapitalRemittanceIndex::SEARCH_FIELDS,
                                                                          query:, default_operator: 'and' })

      @capital_remittances = @capital_remittances.objects
      render "index"
    else
      redirect_to capital_remittances_path(params.to_enum.to_h)
    end
  end

  # GET /capital_remittances/1 or /capital_remittances/1.json
  def show; end

  def generate_docs
    CapitalRemittanceDocJob.perform_later(@capital_remittance.id, current_user.id)
    redirect_to capital_remittance_path(@capital_remittance), notice: "Documentation generation started, please check back in a few mins."
  end

  def allocate_units
    FundUnitsJob.perform_later(@capital_remittance.id, "CapitalRemittance", "Allocation for remittance", current_user.id)
    redirect_to capital_remittance_path(@capital_remittance), notice: "Allocation process started, please check back in a few mins."
  end

  # GET /capital_remittances/new
  def new
    @capital_remittance = CapitalRemittance.new(capital_remittance_params)
    @capital_remittance.entity_id = @capital_remittance.capital_call.entity_id
    @capital_remittance.fund_id = @capital_remittance.capital_call.fund_id

    @capital_remittance.call_amount = @capital_remittance.due_amount
    authorize @capital_remittance
    setup_custom_fields(@capital_remittance)
  end

  # GET /capital_remittances/1/edit
  def edit
    @capital_remittance.status = params[:status] if params[:status]
    @capital_remittance.collected_amount_cents = @capital_remittance.call_amount_cents if @capital_remittance.status == "Paid" && @capital_remittance.collected_amount_cents.zero?

    setup_custom_fields(@capital_remittance)
  end

  # POST /capital_remittances or /capital_remittances.json
  def create
    @capital_remittance = CapitalRemittance.new(capital_remittance_params)
    authorize @capital_remittance
    respond_to do |format|
      if @capital_remittance.save
        format.html { redirect_to capital_remittance_url(@capital_remittance), notice: "Capital remittance was successfully created." }
        format.json { render :show, status: :created, location: @capital_remittance }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_remittance.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_remittances/1 or /capital_remittances/1.json
  def update
    respond_to do |format|
      if @capital_remittance.update(capital_remittance_params)
        format.html { redirect_to capital_remittance_url(@capital_remittance), notice: "Capital remittance was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_remittance }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_remittance.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_remittances/1 or /capital_remittances/1.json
  def destroy
    @capital_remittance.destroy

    respond_to do |format|
      format.html { redirect_to capital_remittances_url, notice: "Capital remittance was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def verify
    @capital_remittance.verified = !@capital_remittance.verified
    @capital_remittance.save!
    redirect_to capital_call_url(@capital_remittance.capital_call, tab: "remittances-tab"), notice: "Successfully updated."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:id])
    authorize @capital_remittance
  end

  # Only allow a list of trusted parameters through.
  def capital_remittance_params
    params.require(:capital_remittance).permit(:entity_id, :fund_id, :capital_call_id, :investor_id, :status, :call_amount, :notes, :verified, properties: {})
  end
end
