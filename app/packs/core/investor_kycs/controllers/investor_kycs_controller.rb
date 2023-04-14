class InvestorKycsController < ApplicationController
  before_action :set_investor_kyc, only: %i[show edit update destroy toggle_verified]
  after_action :verify_authorized, except: %i[index search]

  # GET /investor_kycs or /investor_kycs.json
  def index
    @investor = nil
    @investor_kycs = policy_scope(InvestorKyc)
    if params[:investor_id]
      @investor = Investor.find(params[:investor_id])
      @investor_kycs = @investor_kycs.where(investor_id: params[:investor_id])
    end

    @investor_kycs = @investor_kycs.where(verified: params[:verified] == "true") if params[:verified].present?

    @investor_kycs = @investor_kycs.includes(:investor, :entity)
    @investor_kycs = @investor_kycs.page(params[:page]) if params[:all].blank?

    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json { render json: InvestorKycDatatable.new(params, investor_kycs: @investor_kycs) }
    end
  end

  def search
    query = params[:query]
    if query.present?

      entity_ids = if current_user.curr_role == "advisor"
                     # Advisors can search for KYC across all the entities that they are advisors for
                     Entity.advisor_for(current_user).collect(&:id)
                   else
                     [current_user.entity_id]
                   end

      @investor_kycs = InvestorKycIndex.filter(terms: { entity_id: entity_ids })
                                       .query(query_string: { fields: InvestorKycIndex::SEARCH_FIELDS,
                                                              query:, default_operator: 'and' })
                                       .page(params[:page])
                                       .objects

      render "index"
    else
      redirect_to investor_kycs_path(request.parameters)
    end
  end

  # GET /investor_kycs/1 or /investor_kycs/1.json
  def show; end

  # GET /investor_kycs/new
  def new
    @investor_kyc = InvestorKyc.new(investor_kyc_params)
    authorize(@investor_kyc)
    setup_custom_fields(@investor_kyc)
  end

  # GET /investor_kycs/1/edit
  def edit
    setup_custom_fields(@investor_kyc)
  end

  # POST /investor_kycs or /investor_kycs.json
  def create
    @investor_kyc = InvestorKyc.new(investor_kyc_params)
    authorize(@investor_kyc)
    setup_doc_user(@investor_kyc)

    respond_to do |format|
      if @investor_kyc.save
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully created." }
        format.json { render :show, status: :created, location: @investor_kyc }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_kycs/1 or /investor_kycs/1.json
  def update
    setup_doc_user(@investor_kyc)
    respond_to do |format|
      if @investor_kyc.update(investor_kyc_params)
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_kyc }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  def toggle_verified
    verified_by_id = @investor_kyc.verified ? nil : current_user.id
    respond_to do |format|
      if @investor_kyc.update(verified: !@investor_kyc.verified, verified_by_id:)
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_kyc }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_kycs/1 or /investor_kycs/1.json
  def destroy
    @investor_kyc.destroy

    respond_to do |format|
      format.html { redirect_to investor_kycs_url, notice: "Investor kyc was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_kyc
    @investor_kyc = InvestorKyc.find(params[:id])
    authorize(@investor_kyc)
  end

  # Only allow a list of trusted parameters through.
  def investor_kyc_params
    params.require(:investor_kyc).permit(:investor_id, :entity_id, :user_id, :kyc_type, :full_name, :PAN, :pan_card, :signature, :address, :bank_account_number, :ifsc_code, :bank_verified, :bank_verification_response, :expiry_date, :bank_verification_status, :pan_verified, :pan_verification_response, :pan_verification_status, :comments, :verified, :video, :phone, :form_type_id, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
