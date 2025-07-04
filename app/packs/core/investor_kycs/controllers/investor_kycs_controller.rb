class InvestorKycsController < ApplicationController
  after_action :verify_policy_scoped, only: [:index] # add send_reminder_to_all?

  before_action :set_investor_kyc, only: %i[show edit update destroy toggle_verified generate_docs generate_new_aml_report send_kyc_reminder notify_kyc_required send_notification validate_docs_with_ai preview]
  after_action :verify_authorized, except: %i[index search generate_all_docs edit_my_kyc]

  has_scope :uncalled, type: :boolean
  has_scope :unverified, type: :boolean
  has_scope :agreement_uncalled, type: :boolean
  has_scope :agreement_overcalled, type: :boolean

  # GET /investor_kycs or /investor_kycs.json
  def index
    params[:q] = JSON.parse(params[:q]) if params[:q].is_a?(String)
    fetch_rows

    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json
    end
  end

  def fetch_rows
    authorize(InvestorKyc)
    @q = InvestorKyc.ransack(params[:q])
    @investor_kycs = policy_scope(@q.result).includes(:entity, :investor)
    @investor_kycs = apply_scopes(@investor_kycs)

    @investor = Investor.find(params[:investor_id]) if params[:investor_id].present?

    @investor_kycs = KycSearch.perform(@investor_kycs, current_user, params)

    @pagy, @investor_kycs = pagy(@investor_kycs, limit: params[:per_page]) if params[:all].blank?

    @investor_kycs
  end

  # GET /investor_kycs/1 or /investor_kycs/1.json
  def show; end

  # This can be triggered for any resource which implements with_doc_questions concern
  def validate_docs_with_ai
    authorize(@investor_kyc)
    DocLlmValidationJob.perform_later("InvestorKyc", @investor_kyc.id, current_user.id)
    redirect_to investor_kyc_url(@investor_kyc), notice: "Document validation in progress. Please check back in a few minutes."
  end

  # GET /investor_kycs/new
  def new
    kyc_type = investor_kyc_params[:kyc_type] || "Individual"
    @investor_kyc = kyc_type == "Individual" ? IndividualKyc.new(investor_kyc_params) : NonIndividualKyc.new(investor_kyc_params)
    @investor_kyc.type = @investor_kyc.type_from_kyc_type
    authorize(@investor_kyc)
    setup_custom_fields(@investor_kyc, type: @investor_kyc.type)
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
    if params[:kyc_type].present?
      ActiveRecord::Base.connected_to(role: :writing) do
        # The form is reloaded if the user changes the kyc type
        # when switching from individual to non individual the kyc form custom fields dont work properly as the custom fields have the initial kyc type_custom_field and the js cannot update it as it looks for the updated custom field.
        # explaination of becomes - https://nts.strzibny.name/rails-activerecord-becomes/
        @investor_kyc.kyc_type = params[:kyc_type]
        @investor_kyc.type = @investor_kyc.type_from_kyc_type
        @investor_kyc = @investor_kyc.becomes(@investor_kyc.type.constantize)
        @investor_kyc.save(validate: false)
      end
    end
    setup_custom_fields(@investor_kyc, type: @investor_kyc.type)
  end

  # POST /investor_kycs or /investor_kycs.json
  def create
    @investor_kyc = InvestorKyc.new(investor_kyc_params)
    authorize(@investor_kyc)
    investor_user = current_user.curr_role_investor?
    @investor_kyc.documents.each(&:validate)

    respond_to do |format|
      if InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user:, owner_id: params[:owner_id], owner_type: params[:owner_type]).success?
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully saved." }
        format.json { render :show, status: :created, location: @investor_kyc }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: result[:errors], status: :unprocessable_entity }
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

  def notify_kyc_required
    if @investor_kyc.investor.approved_users.present?
      @investor_kyc.send_kyc_form_to_user = true
      @investor_kyc.send_kyc_form
      msg = "KYC form sent successfully."
      redirect_to investor_kyc_url(@investor_kyc), notice: msg
    else
      msg = "KYC form could not be sent as no user has been assigned to the investor."
      redirect_to investor_kyc_url(@investor_kyc), alert: msg
    end
  end

  def send_notification
    @investor_kyc.updated_notification(msg: params[:message])
    redirect_to investor_kyc_url(@investor_kyc), notice: "Notification sent successfully. Please wait for us to respond to your request."
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
    respond_to do |format|
      investor_user = current_user.curr_role_investor?
      if InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user:).success?
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

  def assign_kyc_data
    @investor_kyc = InvestorKyc.find(investor_kyc_params[:id])
    authorize(@investor_kyc)
    if investor_kyc_params[:kyc_data_id].present?
      @kyc_data = @investor_kyc.kyc_datas.find(investor_kyc_params[:kyc_data_id])
      @investor_kyc.assign_kyc_data(@kyc_data, current_user)
    else
      @investor_kyc.assign_attributes(investor_kyc_params)
      # when CKYC/KRA data is selected once and user goes back then selects no data the images need to be removed (sending nil is not allowed in params)
      @investor_kyc.remove_images
    end
    respond_to do |format|
      if InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user: false).success?
        format.html { redirect_to edit_investor_kyc_path(@investor_kyc), notice: "Investor kyc was successfully updated." }
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_kycs/1 or /investor_kycs/1.json
  def update
    investor_user = current_user.curr_role_investor?
    @investor_kyc.assign_attributes(investor_kyc_params)
    @investor_kyc.documents.each(&:validate)
    respond_to do |format|
      if InvestorKycUpdate.call(investor_kyc: @investor_kyc, investor_user:).success?
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully saved." }
        format.json { render :show, status: :ok, location: @investor_kyc }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: result[:errors], status: :unprocessable_entity }
      end
    end
  end

  def toggle_verified
    investor_user = current_user.curr_role_investor?
    verified_by_id = @investor_kyc.verified ? nil : current_user.id
    @investor_kyc.assign_attributes(verified: !@investor_kyc.verified, verified_by_id:)
    status = @investor_kyc.verified ? "verified" : "unverified"

    respond_to do |format|
      if InvestorKycUpdate.call(investor_kyc: @investor_kyc, investor_user:).success?
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully #{status}." }
        format.json { render :show, status: :ok, location: @investor_kyc }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: result[:errors], status: :unprocessable_entity }
      end
    end
  end

  def generate_docs
    if params["_method"] == "patch"

      if params[:document_template_ids].present? && Date.parse(params[:start_date]) <= Date.parse(params[:end_date])
        KycDocGenJob.perform_later(@investor_kyc.id, params[:document_template_ids],
                                   params[:start_date], params[:end_date], current_user.id)

        redirect_to investor_kyc_path(@investor_kyc), notice: "Document generation in progress. Please check back in a few minutes."
      else
        redirect_to request.referer, alert: "Invalid dates or document template."
      end
    end
  end

  def generate_all_docs
    # We get a ransack query for the KYCs for which we want to generate the docs
    @q = InvestorKyc.ransack(params[:q])
    # Get the kycs for the query
    @investor_kycs = policy_scope(@q.result.distinct).includes(:entity, :investor)
    if request.post?
      if params[:document_template_ids].present? && Date.parse(params[:start_date]) <= Date.parse(params[:end_date])
        # Send the kyc ids, document template ids, start date and end date to the job
        KycDocGenJob.perform_later(@investor_kycs.pluck(:id), params[:document_template_ids], params[:start_date], params[:end_date], current_user.id, entity_id: params[:entity_id])

        redirect_to investor_kycs_url(q: params[:q].to_unsafe_h), notice: "Document generation in progress. Please check back in a few minutes."
      else
        redirect_to generate_all_docs_investor_kycs_url(q: params[:q].to_unsafe_h), alert: "Invalid dates or document template."
      end
    end
  end

  def generate_new_aml_report
    authorize(@investor_kyc)
    @investor_kyc.generate_aml_report(current_user.id)
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
    @bread_crumbs = { KYCs: investor_kycs_path, "#{@investor_kyc.full_name}": investor_kyc_path(@investor_kyc) }
  end

  # Only allow a list of trusted parameters through.
  def investor_kyc_params
    param_name = if params[:individual_kyc].present?
                   :individual_kyc
                 elsif params[:non_individual_kyc].present?
                   :non_individual_kyc
                 else
                   :investor_kyc
                 end

    params.require(param_name).permit(:id, :investor_id, :entity_id, :user_id, :kyc_data_id, :kyc_type, :full_name, :birth_date, :PAN, :pan_card, :signature, :address, :corr_address, :bank_account_number, :ifsc_code, :bank_branch, :bank_account_type, :bank_name, :bank_verified, :type, :bank_verification_response, :expiry_date, :esign_emails, :bank_verification_status, :pan_verified, :residency, :pan_verification_response, :pan_verification_status, :comments, :completed_by_investor, :verified, :phone, :form_type_id, :send_kyc_form_to_user, :agreement_unit_type, :agreement_committed_amount, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end

  def commit_param
    params.require(:commit)
  end
end
