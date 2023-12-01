class InvestorKycsController < ApplicationController
  after_action :verify_policy_scoped, only: [:index] # add send_reminder_to_all?

  before_action :set_investor_kyc, only: %i[show edit update destroy toggle_verified generate_docs generate_new_aml_report send_kyc_reminder]
  after_action :verify_authorized, except: %i[index search generate_all_docs edit_my_kyc]

  # GET /investor_kycs or /investor_kycs.json
  def index
    @investor = nil
    @investor_kycs = policy_scope(InvestorKyc)
    authorize(InvestorKyc)
    @investor_kycs = @investor_kycs.where(id: search_ids) if params[:search] && params[:search][:value].present?
    if params[:investor_id]
      @investor = Investor.find(params[:investor_id])
      @investor_kycs = @investor_kycs.where(investor_id: params[:investor_id])
    end

    @investor_kycs = @investor_kycs.where(verified: params[:verified] == "true") if params[:verified].present?

    @investor_kycs = @investor_kycs.includes(:investor, :entity)
    @investor_kycs = @investor_kycs.page(params[:page]) if params[:all].blank? && params[:search].blank?

    # The distinct clause is there because IAs can access only KYCs that belong to thier funds
    # See policy_scope - this query returns dups
    @investor_kycs = @investor_kycs.distinct

    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json { render json: InvestorKycDatatable.new(params, investor_kycs: @investor_kycs) }
    end
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    InvestorKycIndex.filter(terms: { entity_id: entity_ids })
                    .query(query_string: { fields: InvestorKycIndex::SEARCH_FIELDS,
                                           query:, default_operator: 'and' }).map(&:id)
  end

  # GET /investor_kycs/1 or /investor_kycs/1.json
  def show; end

  # GET /investor_kycs/new
  def new
    @investor_kyc = InvestorKyc.new(investor_kyc_params)
    authorize(@investor_kyc)
    setup_custom_fields(@investor_kyc)
  end

  def edit_my_kyc
    # We have the current_entity from the url subdomain or from a specific param in the notice
    current_entity = params[:current_entity_id].present? ? Entity.where(id: params[:current_entity_id]).first : @current_entity

    if current_entity.blank? 
      redirect_to investor_kycs_path, info: "Please select the kyc you want to update." 
    else 
      # Find the investor for the current user in the current_entity
      investor = current_entity.investors.joins(:investor_accesses).where(investor_accesses: { user_id: current_user.id }).first

      if investor.blank? 
        redirect_to investor_kycs_path, info: "Please select the kyc you want to update." 
      else

        # Find and redirect to kyc if it exists, else redirect to new kyc
        kyc = current_entity.investor_kycs.where(investor_id: investor.id).last
        if kyc.present?
          redirect_to edit_investor_kyc_path(kyc)
        else
          redirect_to new_investor_kyc_path(investor_id: investor.id)
        end
      end
    end
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
        format.html { save_and_upload }
        format.json { render :show, status: :created, location: @investor_kyc }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  def send_kyc_reminder
    if @investor_kyc.investor.approved_users.present?
      @investor_kyc.send_kyc_form(reminder: true)
      msg = "KYC Reminder sent successfully."
      redirect_to investor_kyc_url(@investor_kyc), notice: msg
    else
      msg = "KYC Reminder could not be sent as no user has been assigned to the investor."
      redirect_to investor_kyc_url(@investor_kyc), alert: msg
    end
  end

  def send_kyc_reminder_to_all
    entity_id = current_user.entity_id
    @investor_kycs = policy_scope(InvestorKyc)
    authorize(InvestorKyc)

    @investor_kycs.where(entity_id:, verified: false).find_each do |kyc|
      kyc.send_kyc_form(reminder: true)
    end
    redirect_to investor_kycs_url, notice: "KYC Reminder sent successfully."
  end

  def compare_kyc_datas
    @investor_kyc = InvestorKyc.new(investor_kyc_params)
    authorize(@investor_kyc)
    setup_doc_user(@investor_kyc)
    respond_to do |format|
      if @investor_kyc.save
        format.html do
          if commit_param == "Continue without CKYC/KRA"
            redirect_to edit_investor_kyc_path(@investor_kyc)
          else
            redirect_to compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @investor_kyc.id)
          end
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  def save_and_upload
    if params[:commit] == "Save & Upload Documents"
      redirect_to new_document_url(document: { entity_id: @investor_kyc.entity_id, owner_id: @investor_kyc.id, owner_type: "InvestorKyc" }, display_status: true), notice: "Investor kyc was successfully saved. Please upload the required documents for the KYC."
    else
      redirect_to investor_kyc_url(@investor_kyc, display_status: true), notice: "Investor kyc was successfully saved. Please upload the required documents for the KYC."
    end
  end

  def assign_kyc_data
    @investor_kyc = InvestorKyc.find(investor_kyc_params[:id])
    authorize(@investor_kyc)
    if investor_kyc_params[:kyc_data_id].present?
      @kyc_data = @investor_kyc.kyc_datas.find(investor_kyc_params[:kyc_data_id])
      @investor_kyc.assign_kyc_data(@kyc_data)
    else
      @investor_kyc.assign_attributes(investor_kyc_params)
      # when CKYC/KRA data is selected once and user goes back then selects no data the images need to be removed (sending nil is not allowed in params)
      @investor_kyc.signature = nil
      @investor_kyc.pan_card = nil
    end
    respond_to do |format|
      if @investor_kyc.save
        format.html { redirect_to edit_investor_kyc_path(@investor_kyc), notice: "Investor kyc was successfully updated." }
      else
        format.html { redirect_to edit_investor_kyc_path(@investor_kyc), status: :unprocessable_entity }
      end
      format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
    end
  end

  # PATCH/PUT /investor_kycs/1 or /investor_kycs/1.json
  def update
    setup_doc_user(@investor_kyc)
    respond_to do |format|
      if @investor_kyc.update(investor_kyc_params)
        format.html { save_and_upload }
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

  def generate_docs
    if params["_method"] == "patch"

      if params[:document_template_ids].present? && Date.parse(params[:start_date]) <= Date.parse(params[:end_date])
        KycDocGenJob.perform_later(@investor_kyc.id, params[:document_template_ids],
                                   params[:start_date], params[:end_date], user_id: current_user.id)

        redirect_to investor_kyc_url(@investor_kyc), notice: "Document generation in progress. Please check back in a few minutes."
      else
        redirect_to generate_docs_investor_kycs_url, alert: "Invalid dates or document template."
      end
    end
  end

  def generate_all_docs
    if request.post?
      if params[:document_template_ids].present? && Date.parse(params[:start_date]) <= Date.parse(params[:end_date])
        KycDocGenJob.perform_later(nil, params[:document_template_ids], params[:start_date], params[:end_date],
                                   user_id: current_user.id, entity_id: params[:entity_id])

        redirect_to investor_kycs_url, notice: "Document generation in progress. Please check back in a few minutes."
      else
        redirect_to generate_all_docs_investor_kycs_url, alert: "Invalid dates or document template."
      end
    end
  end

  def generate_new_aml_report
    authorize(@investor_kyc)
    @investor_kyc.generate_aml_report
    redirect_to investor_kyc_url(@investor_kyc), notice: "AML report generation initiated."
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
    params.require(:investor_kyc).permit(:id, :investor_id, :entity_id, :user_id, :kyc_data_id, :kyc_type, :full_name, :birth_date, :PAN, :pan_card, :signature, :address, :corr_address, :bank_account_number, :ifsc_code, :bank_verified, :bank_verification_response, :expiry_date, :bank_verification_status, :pan_verified, :residency, :pan_verification_response, :pan_verification_status, :comments, :verified, :video, :phone, :form_type_id, :send_kyc_form_to_user, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end

  def commit_param
    params.require(:commit)
  end
end
