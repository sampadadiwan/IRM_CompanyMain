class CapitalCommitmentsController < ApplicationController
  before_action :set_capital_commitment, only: %i[show edit update destroy generate_documentation
                                                  report generate_soa generate_soa_form transfer_fund_units]

  after_action :verify_authorized, only: %i[show edit update destroy generate_documentation
                                            report generate_soa generate_soa_form]

  # GET /capital_commitments or /capital_commitments.json
  def index
    @q = CapitalCommitment.ransack(params[:q])

    @capital_commitments = policy_scope(@q.result).includes(:entity, :fund, :investor_kyc, :investor)

    @capital_commitments = @capital_commitments.where(id: search_ids) if params[:search] && params[:search][:value].present?

    @capital_commitments = @capital_commitments.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @capital_commitments = @capital_commitments.where(investor_id: params[:investor_id]) if params[:investor_id].present?
    @capital_commitments = @capital_commitments.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @capital_commitments = @capital_commitments.where(onboarding_completed: params[:onboarding_completed]) if params[:onboarding_completed].present?

    template = "index"
    if params[:group_fields].present?
      @data_frame = CapitalCommitmentDf.new.df(@capital_commitments, current_user, params)
      @adhoc_json = @data_frame.to_a.to_json
      template = params[:template].presence || "index"
    elsif params[:all].blank?
      @capital_commitments = @capital_commitments.page(params[:page])
      @capital_commitments = @capital_commitments.per(params[:per_page].to_i) if params[:per_page].present?
    end

    respond_to do |format|
      format.html do
        render template
      end
      format.xlsx
      format.json do
        render json: CapitalCommitmentDatatable.new(params, capital_commitments: @capital_commitments) if params[:jbuilder].blank?
      end
    end
  end

  def documents
    capital_commitment_ids = policy_scope(CapitalCommitment).pluck(:id)
    kyc_ids = policy_scope(InvestorKyc).joins(:investor).pluck(:id)
    @documents = Document.where(owner_id: capital_commitment_ids, owner_type: "CapitalCommitment").or(Document.where(owner_id: kyc_ids, owner_type: "InvestorKyc"))

    @documents = @documents.where(owner_tag: "Generated", approved: true).or(@documents.where.not(owner_tag: "Generated")).or(@documents.where(owner_tag: nil)).not_template if current_user.curr_role_investor?

    @documents = @documents.order(id: :desc)

    @no_folders = false
    render "documents"
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    term = { entity_id: current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user
    # Only return first 100 results
    index_search = CapitalCommitmentIndex.filter(term:)
                                         .query(query_string: { fields: CapitalCommitmentIndex::SEARCH_FIELDS,
                                                                query:, default_operator: 'and' })

    index_search = index_search.filter(term: { fund_id: params[:fund_id] }) if params[:fund_id].present?
    index_search = index_search.per(100)

    index_search.map(&:id)
  end

  def transfer_fund_units
    if request.post?
      fund = @capital_commitment.fund
      from_commitment = @capital_commitment
      price = params[:price].to_d
      premium = params[:premium].to_d
      quantity = params[:quantity].to_d
      transfer_date = params[:transfer_date]
      to_folio_id = params[:to_folio_id]

      valid_params = params.to_unsafe_h.slice(:to_folio_id, :quantity, :price, :premium, :transfer_date)
      # Check if the to_folio_id is valid
      to_commitment = @capital_commitment.fund.capital_commitments.find_by(folio_id: to_folio_id)

      if to_commitment.blank?
        # Redirect back to the form with an error message
        redirect_to transfer_fund_units_capital_commitment_path(@capital_commitment, **valid_params), alert: "Invalid folio #{params[:to_folio_id]}"
      else
        # Check if the user is authorized to transfer fund units
        authorize to_commitment, :transfer_fund_units?
        # Transfer fund units using the TB
        result = FundUnitTransferService.call(from_commitment:, to_commitment:, fund:, price:, premium:, quantity:, transfer_date:)
        if result.success?
          # Redirect to the fund units tab
          redirect_to capital_commitment_url(@capital_commitment, tab: "fund-units-tab"), notice: "Units transferred successfully"
        else
          # Redirect back to the form with an error message
          redirect_to transfer_fund_units_capital_commitment_path(@capital_commitment, **valid_params), alert: result[:error]
        end
      end
    end
  end

  def report
    render params[:report]
  end

  # GET /capital_commitments/1 or /capital_commitments/1.json
  def show
    respond_to do |format|
      format.html
      format.pdf do
        FerrumPdf.browser(timeout: 60)
        pdf = render_pdf
        send_data pdf, disposition: :inline, filename: "#{@capital_commitment.folio_id}.pdf"
      end
    end
  end

  def generate_documentation
    CapitalCommitmentDocJob.perform_later(@capital_commitment.fund_id, @capital_commitment.id, current_user.id, template_id: params[:template_id])

    redirect_to capital_commitment_url(@capital_commitment), notice: "Documentation generation started, please check back in a few mins."
  end

  # Only for generating SOA form for the selected commitment
  def generate_soa_form; end

  # Generate the for the selected commitment, based on the start and end dates
  def generate_soa
    if params[:start_date].present? &&
       params[:end_date].present? &&
       Date.parse(params[:start_date]) <= Date.parse(params[:end_date])

      if params[:for] == "Investing Entity"
        # Generate SOA combining all the commitments of the investing entity
        KycDocGenJob.perform_later(@capital_commitment.investor_kyc_id, params[:template_id], params[:start_date], params[:end_date], current_user.id, entity_id: @capital_commitment.entity_id, options: { fund_id: @capital_commitment.fund_id, capital_commitment_id: @capital_commitment.id })
      else
        # Generate SOA for the selected commitment only
        CapitalCommitmentSoaJob.perform_later(@capital_commitment.fund_id, @capital_commitment.id, params[:start_date], params[:end_date], current_user.id, template_id: params[:template_id])
      end

      # All done, redirect back to the capital commitment
      redirect_to capital_commitment_url(@capital_commitment), notice: "Documentation generation started, please check back in a few mins."
    else
      redirect_to request.referer, alert: "Please provide valid start and end dates"
    end
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
      if CapitalCommitmentCreate.call(capital_commitment: @capital_commitment).success?
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
    @capital_commitment.assign_attributes(capital_commitment_params)
    setup_doc_user(@capital_commitment)

    respond_to do |format|
      if CapitalCommitmentUpdate.call(capital_commitment: @capital_commitment).success?
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
    params.require(:capital_commitment).permit(:feeder_fund_id, :entity_id, :investor_id, :fund_id, :committed_amount, :collected_amount, :notes, :folio_id, :investor_signatory_id, :investor_kyc_id, :onboarding_completed, :form_type_id, :unit_type, :fund_close, :virtual_bank_account, :folio_currency, :is_feeder_fund, :folio_committed_amount, :esign_emails, :commitment_date, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
