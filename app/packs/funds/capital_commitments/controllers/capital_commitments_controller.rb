class CapitalCommitmentsController < ApplicationController
  before_action :set_capital_commitment, only: %i[show edit update destroy generate_documentation
                                                  generate_esign_link report]

  # GET /capital_commitments or /capital_commitments.json
  def index
    @capital_commitments = policy_scope(CapitalCommitment).includes(:entity, :investor, :fund)
    @capital_commitments = @capital_commitments.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_commitments = @capital_commitments.where(onboarding_completed: params[:onboarding_completed]) if params[:onboarding_completed].present?

    @capital_commitments = @capital_commitments.page(params[:page]) if params[:all].blank?
  end

  def report
    render params[:report]
  end

  def search
    query = params[:query]

    if query.present?
      if params[:fund_id].present?
        # Search in fund provided user is authorized
        @fund = Fund.find(params[:fund_id])
        authorize(@fund, :show?)
        term = { fund_id: @fund.id }
      else
        # Search in users entity only
        term = { entity_id: current_user.entity_id }
      end

      @capital_commitments = CapitalCommitmentIndex.filter(term:)
                                                   .query(query_string: { fields: CapitalCommitmentIndex::SEARCH_FIELDS,
                                                                          query:, default_operator: 'and' })

      @capital_commitments = @capital_commitments.objects
      render "index"
    else
      redirect_to capital_commitments_path(params.to_enum.to_h)
    end
  end

  # GET /capital_commitments/1 or /capital_commitments/1.json
  def show; end

  def generate_documentation
    CapitalCommitmentDocJob.perform_later(@capital_commitment.id, current_user.id)
    redirect_to capital_commitment_url(@capital_commitment), notice: "Documentation generation started, please check back in a few mins."
  end

  def generate_esign_link
    CapitalCommitmentGenerateEsignJob.perform_later(@capital_commitment.id)
    redirect_to capital_commitment_url(@capital_commitment), notice: "Esign generation started, please check back in a few mins."
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
      format.html { redirect_to capital_commitments_url, notice: "Capital commitment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_commitment
    @capital_commitment = CapitalCommitment.find(params[:id])
    authorize @capital_commitment
  end

  # Only allow a list of trusted parameters through.
  def capital_commitment_params
    params.require(:capital_commitment).permit(:entity_id, :investor_id, :fund_id, :committed_amount, :collected_amount, :notes, :folio_id, :investor_signatory_id, :investor_kyc_id, :onboarding_completed, :investor_signature_types, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
