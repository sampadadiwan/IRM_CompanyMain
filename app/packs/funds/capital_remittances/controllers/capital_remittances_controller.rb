class CapitalRemittancesController < ApplicationController
  before_action :set_capital_remittance, only: %i[show edit update destroy verify generate_docs allocate_units send_notification]

  # GET /capital_remittances or /capital_remittances.json
  def index
    fetch_rows
    if params[:all].blank?
      page = params[:page] || 1
      @capital_remittances = @capital_remittances.page(page)
      @capital_remittances = @capital_remittances.per(params[:per_page].to_i) if params[:per_page].present?
    end

    respond_to do |format|
      format.html
      format.xlsx
      format.json
    end
  end

  def fetch_rows
    @q = CapitalRemittance.ransack(params[:q])

    @capital_remittances = policy_scope(@q.result).includes(:fund, :capital_call, :entity, capital_commitment: :fund)

    @capital_remittances = @capital_remittances.where(id: search_ids) if params[:search] && params[:search][:value].present?

    @capital_remittances = @capital_remittances.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_remittances = @capital_remittances.where(status: params[:status].split(",")) if params[:status].present?
    @capital_remittances = @capital_remittances.where(verified: params[:verified] == "true") if params[:verified].present?
    if params[:capital_call_id].present?
      @capital_remittances = @capital_remittances.where(capital_call_id: params[:capital_call_id])
      @capital_call = CapitalCall.find(params[:capital_call_id])
    end
    if params[:capital_commitment_id].present?
      @capital_remittances = @capital_remittances.where(capital_commitment_id: params[:capital_commitment_id])
      @capital_commitment = CapitalCommitment.find(params[:capital_commitment_id])
    end
    @capital_remittances = @capital_remittances.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?

    @capital_remittances
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    term = { entity_id: current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user
    # Only return first 100 results
    index_search = CapitalRemittanceIndex.filter(term:)
                                         .query(query_string: { fields: CapitalRemittanceIndex::SEARCH_FIELDS,
                                                                query:, default_operator: 'and' }).per(100)

    # Filter by fund, capital_distribution and capital_commitment
    index_search = index_search.filter(term: { fund_id: params[:fund_id] }) if params[:fund_id].present?
    index_search = index_search.filter(term: { capital_call_id: params[:capital_call_id] }) if params[:capital_call_id].present?
    index_search = index_search.filter(term: { capital_commitment_id: params[:capital_commitment_id] }) if params[:capital_commitment_id].present?
    index_search.map(&:id)
  end

  # GET /capital_remittances/1 or /capital_remittances/1.json
  def show; end

  def generate_docs
    CapitalRemittanceDocJob.perform_later(@capital_remittance.capital_call_id, @capital_remittance.id, current_user.id)
    redirect_to capital_remittance_path(@capital_remittance), notice: "Documentation generation started, please check back in a few mins."
  end

  def allocate_units
    FundUnitsJob.perform_later(@capital_remittance.id, "CapitalRemittance", "Allocation for remittance", current_user.id)
    redirect_to capital_remittance_path(@capital_remittance), notice: "Allocation process started, please check back in a few mins."
  end

  def send_notification
    reminder = @capital_remittance.notification_sent
    @capital_remittance.send_notification(reminder:)
    redirect_to capital_remittance_path(@capital_remittance), notice: "Sent notification."
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
      if CapitalRemittanceCreate.call(capital_remittance: @capital_remittance).success?
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
    @capital_remittance.assign_attributes(capital_remittance_params)
    respond_to do |format|
      if CapitalRemittanceUpdate.call(capital_remittance: @capital_remittance).success?
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
    result = CapitalRemittanceVerify.call(capital_remittance: @capital_remittance)
    default_columns_map = if current_user.curr_role == "investor"
                            CapitalRemittance::INVESTOR_STANDARD_COLUMNS
                          else
                            CapitalRemittance::STANDARD_COLUMNS
                          end

    @capital_remittance = @capital_remittance.decorate
    @ransack_table_header = RansackTableHeader.new(CapitalRemittance, default_columns_map: default_columns_map, current_user: current_user, records: [@capital_remittance], q: nil, turbo_frame: nil)
    notice = result.success? ? "Successfully verified." : "Failed to verify. #{@capital_remittance.errors}"
    respond_to do |format|
      format.html { redirect_back fallback_location: capital_call_url(@capital_remittance.capital_call, tab: "remittances-tab"), notice: }
      format.json { render :show, status: :ok, location: @capital_remittance }
      format.turbo_stream { render :verify }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:id])
    authorize @capital_remittance
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_remittance.fund.name}": fund_path(@capital_remittance.fund),
                      "#{@capital_remittance.capital_call}": capital_call_path(@capital_remittance.capital_call),
                      "#{@capital_remittance}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_remittance_params
    params.require(:capital_remittance).permit(:entity_id, :fund_id, :capital_call_id, :investor_id, :status, :call_amount, :notes, :remittance_date, :verified, :form_type_id, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
