class CapitalCommitmentsController < ApplicationController
  before_action :set_capital_commitment, only: %i[show edit update destroy generate_documentation
                                                  report generate_soa generate_soa_form]

  after_action :verify_authorized, only: %i[show edit update destroy generate_documentation
                                            report generate_soa generate_soa_form]

  # GET /capital_commitments or /capital_commitments.json
  def index
    @q = CapitalCommitment.ransack(params[:q])

    @capital_commitments = policy_scope(@q.result).includes(:entity, :fund, :investor_kyc)

    @capital_commitments = @capital_commitments.where(id: search_ids) if params[:search] && params[:search][:value].present?

    @capital_commitments = @capital_commitments.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_commitments = @capital_commitments.where(investor_id: params[:investor_id]) if params[:investor_id].present?
    @capital_commitments = @capital_commitments.where(onboarding_completed: params[:onboarding_completed]) if params[:onboarding_completed].present?

    @capital_commitments = @capital_commitments.page(params[:page]) if params[:all].blank?

    respond_to do |format|
      format.html
      format.xlsx
      format.json { render json: CapitalCommitmentDatatable.new(params, capital_commitments: @capital_commitments) }
    end
  end

  def documents
    capital_commitment_ids = policy_scope(CapitalCommitment).pluck(:id)
    @documents = Document.where(owner_id: capital_commitment_ids, owner_type: "CapitalCommitment")
    @documents = @documents.order(id: :desc)

    @no_folders = false
    render "documents"
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    term = { entity_id: current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user
    index_search = CapitalCommitmentIndex.filter(term:)
                                         .query(query_string: { fields: CapitalCommitmentIndex::SEARCH_FIELDS,
                                                                query:, default_operator: 'and' })
    index_search = index_search.filter(term: { fund_id: params[:fund_id] }) if params[:fund_id].present?

    index_search.map(&:id)
  end

  def report
    render params[:report]
  end

  # GET /capital_commitments/1 or /capital_commitments/1.json
  def show; end

  def generate_documentation
    CapitalCommitmentDocJob.perform_later(@capital_commitment.id, current_user.id)
    redirect_to capital_commitment_url(@capital_commitment), notice: "Documentation generation started, please check back in a few mins."
  end

  def generate_soa_form; end

  def generate_soa
    CapitalCommitmentSoaJob.perform_later(@capital_commitment.id, params[:start_date], params[:end_date], user_id: current_user.id, template_name: params[:template_name])
    redirect_to capital_commitment_url(@capital_commitment), notice: "Documentation generation started, please check back in a few mins."
  end

  # GET /capital_commitments/new
  def new
    @capital_commitment = CapitalCommitment.new(capital_commitment_params)
    @capital_commitment.entity_id = @capital_commitment.fund.entity_id
    authorize @capital_commitment
    setup_custom_fields(@capital_commitment)
  end

  # GET /capital_commitments/1/edit
  def edit
    setup_custom_fields(@capital_commitment)
  end

  # POST /capital_commitments or /capital_commitments.json
  def create
    @capital_commitment = CapitalCommitment.new(capital_commitment_params)
    @capital_commitment.entity_id = @capital_commitment.fund.entity_id
    authorize @capital_commitment
    setup_doc_user(@capital_commitment)

    respond_to do |format|
      if @capital_commitment.save
        format.html { redirect_to capital_commitment_url(@capital_commitment), notice: "Capital commitment was successfully created." }
        format.json { render :show, status: :created, location: @capital_commitment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_commitment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_commitments/1 or /capital_commitments/1.json
  def update
    setup_doc_user(@capital_commitment)

    respond_to do |format|
      if @capital_commitment.update(capital_commitment_params)
        format.html { redirect_to capital_commitment_url(@capital_commitment), notice: "Capital commitment was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_commitment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_commitment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_commitments/1 or /capital_commitments/1.json
  def destroy
    @capital_commitment.destroy

    respond_to do |format|
      format.html { redirect_to fund_path(@capital_commitment.fund), notice: "Capital commitment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_commitment
    @capital_commitment = CapitalCommitment.find(params[:id])
    authorize @capital_commitment
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_commitment.fund.name}": fund_path(@capital_commitment.fund),
                      "#{@capital_commitment}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_commitment_params
    params.require(:capital_commitment).permit(:entity_id, :investor_id, :fund_id, :committed_amount, :collected_amount, :notes, :folio_id, :investor_signatory_id, :investor_kyc_id, :onboarding_completed, :form_type_id, :unit_type, :fund_close, :virtual_bank_account, :folio_currency, :feeder_fund, :folio_committed_amount, :commitment_type, :commitment_date, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
