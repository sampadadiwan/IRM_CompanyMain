class InvestorKycsController < ApplicationController
  after_action :verify_policy_scoped, only: [:index] # add send_reminder_to_all?

  before_action :set_investor_kyc, only: %i[show edit update destroy toggle_verified generate_docs generate_new_aml_report send_kyc_reminder notify_kyc_required send_notification validate_docs_with_ai preview download_kra_data fetch_ckyc_data assign_kyc_data]
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

  def esign_emails
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    authorize(@investor_kyc)
    @esign_emails = params[:esign_emails].presence || @investor_kyc.esign_emails
  end

  # This can be triggered for any resource which implements with_doc_questions concern
  def validate_docs_with_ai
    authorize(@investor_kyc)
    DocLlmValidationJob.perform_later("InvestorKyc", @investor_kyc.id, current_user.id)
    redirect_to investor_kyc_url(@investor_kyc), notice: "Document validation in progress. Please check back in a few minutes."
  end

  # GET /investor_kycs/new
  def new
    kyc_type = investor_kyc_params[:kyc_type] || "Individual"
    # Create the appropriate KYC type based on the kyc_type parameter
    @investor_kyc = kyc_type == "Individual" ? IndividualKyc.new(investor_kyc_params) : NonIndividualKyc.new(investor_kyc_params)
    @investor_kyc.type = @investor_kyc.type_from_kyc_type
    # If the investor is present, set the full_name to the investor's name
    @investor_kyc.full_name = @investor_kyc.investor.investor_name if @investor_kyc.investor.present? && @investor_kyc.individual?

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

    @form = "form"
    # Show CKYC/KRA form if CKYC or KRA is enabled for the entity and the current user is not the owner of the kyc and the kyc does not have any ckyc or kra data
    # This means the first time around after the investor is sent the KYC for completion they will see the CKYC/KRA form
    @form = "initial_form" if @investor_kyc.entity.ckyc_or_kra_enabled? && current_user.entity_id != @investor_kyc.entity_id && @investor_kyc.ckyc_data.blank? && @investor_kyc.kra_data.blank?

    render :edit, locals: { form: @form }
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

  # This method handles both creating a new InvestorKyc or updating an existing one,
  # validates its documents, and based on user actions, redirects to CKYC/KRA fetch steps or edit view.
  def compare_kyc_datas
    # Load or initialize the InvestorKyc based on the presence of ID
    @investor_kyc = if investor_kyc_params[:id].present?
                      InvestorKyc.find(investor_kyc_params[:id])
                    else
                      InvestorKyc.new(investor_kyc_params)
                    end

    # Ensure current user is authorized to perform this action
    authorize(@investor_kyc)

    # Run service object to upsert (create or update) the InvestorKyc
    result = InvestorKycUpserter.call(params: investor_kyc_params, current_user: current_user)
    @investor_kyc = result.investor_kyc

    # Broadcast an informational alert to the user
    UserAlert.new(message: "Creating KYC...", user_id: current_user.id, level: "info").broadcast if current_user.present?

    if result.success?
      # Case when user opts to skip CKYC/KRA or PAN is not provided
      if commit_param == "Continue without CKYC/KRA" || investor_kyc_params[:PAN].blank?
        msg = "CKYC/KRA skipped"
        msg += " as PAN is not provided." if investor_kyc_params[:PAN].blank?
        redirect_to edit_investor_kyc_path(@investor_kyc), notice: msg
      else
        # Determine if CKYC or KRA is enabled for this entity
        ckyc_enabled = @investor_kyc.entity.permissions.enable_ckyc?
        kra_enabled = @investor_kyc.entity.permissions.enable_kra?

        # Redirect to appropriate data fetch flow
        if kra_enabled
          redirect_to download_kra_data_investor_kyc_path(id: @investor_kyc.id, phone: investor_kyc_params[:phone], back_to: params[:back_to])
        elsif ckyc_enabled
          redirect_to fetch_ckyc_data_investor_kyc_path(id: @investor_kyc.id, phone: investor_kyc_params[:phone], back_to: params[:back_to])
        else
          # Neither CKYC nor KRA enabled
          back_to = params[:back_to] || edit_investor_kyc_path(@investor_kyc)
          redirect_to back_to, notice: "CKYC/KRA not enabled for this entity."
        end
      end
    else
      # Render form with error messages
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: result.errors, status: :unprocessable_entity }
      end
    end
  end

  # Step 1: KRA Data Fetch Flow
  def download_kra_data
    if @investor_kyc.birth_date.blank?
      # KRA fetch requires DOB, show error if missing
      kra_msg = "KRA Data could not be fetched as Date Of Birth is missing."
      flash.now[:alert] = kra_msg
      @kra_result = { success: false, message: kra_msg }
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        UserAlert.new(message: "Initialising KRA Data Object...", user_id: current_user.id, level: "info").broadcast if current_user.present?

        # Create the KRA data object
        @kra_data = CkycKraService.new.fetch_kra_data(@investor_kyc, phone: params[:phone], create: true)

        # If object created, attempt to fetch actual KRA data
        kra_success, kra_msg = if @kra_data.present?
                                 UserAlert.new(message: "Fetching KRA Data...", user_id: current_user.id, level: "info").broadcast if current_user.present?
                                 CkycKraService.new.get_kra_data(@kra_data)
                               else
                                 [false, "KRA Data creation Failed"]
                               end
        @kra_result = { success: kra_success, message: kra_msg }
      end

      # Show results to user
      if @kra_result[:success]
        flash.now[:notice] = @kra_result[:message]
      else
        flash.now[:alert] = @kra_result[:message]
        @investor_kyc.errors.add(:base, @kra_result[:message])
      end
    end

    @ckyc_enabled = @investor_kyc.entity.permissions.enable_ckyc?

    # Render view with fetched KRA data and additional context
    render :fetch_kra_data, locals: { kra_data: @kra_data, kra_result: @kra_result, ckyc_enabled: @ckyc_enabled, phone: params[:phone], back_to: params[:back_to] }
  end

  # Step 2: CKYC Data Fetch + OTP Trigger Flow
  def fetch_ckyc_data
    # Validate phone number before proceeding
    if params[:phone].blank? || params[:phone].length != 10
      redirect_to compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @investor_kyc.id), alert: "Phone number is required to fetch CKYC data using OTP."
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        UserAlert.new(message: "Initialising CKYC Data Object...", user_id: current_user.id, level: "info").broadcast if current_user.present?

        # Create CKYC data record for the investor
        @ckyc_data = CkycKraService.new.fetch_ckyc_data(@investor_kyc, phone: params[:phone], create: true)

        UserAlert.new(message: "Searching CKYC Data...", user_id: current_user.id, level: "info").broadcast if current_user.present?

        # If data creation was successful, search CKYC and trigger OTP
        @ckyc_success, @ckyc_msg, @request_id = if @ckyc_data.present?
                                                  CkycKraService.new.search_ckyc_data_and_send_otp(@ckyc_data)
                                                else
                                                  [false, "CKYC data creation failed.", nil]
                                                end
      end

      if @ckyc_success
        # OTP sent successfully, render OTP input view
        flash.now[:notice] = @ckyc_msg
        render "kyc_datas/enter_ckyc_otp", locals: { ckyc_data: @ckyc_data, request_id: @request_id, back_to: compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @investor_kyc.id) }
      else
        # Error in fetching/sending OTP
        redirect_to compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @investor_kyc.id), alert: @ckyc_msg
      end
    end
  end

  # Used to create an InvestorKyc and send it to the investor for completion
  def create_and_send_kyc_to_investor
    @investor_kyc = InvestorKyc.new(investor_kyc_params)
    authorize(@investor_kyc)

    # Check if the current role is an investor (affects KYC assignment)
    investor_user = current_user.curr_role_investor?

    # Validate attached documents before submission
    @investor_kyc.documents.each(&:validate)

    # Call service to persist and notify
    result = InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user:, owner_id: params[:owner_id], owner_type: params[:owner_type])

    respond_to do |format|
      if result.success?
        format.html { redirect_to request.referer, notice: "Investor KYC will be sent to investor" }
        format.json { render :show, status: :created, location: @investor_kyc }
      else
        format.html do
          flash.now[:alert] = "Investor KYC could not be created. #{result[:errors].join(', ')}"
          render :new, status: :unprocessable_entity
        end
        format.json { render json: result[:errors], status: :unprocessable_entity }
      end
    end
  end

  # Assigns a selected KYC data record to an InvestorKyc and updates it
  def assign_kyc_data
    if investor_kyc_params[:kyc_data_id].present?
      # Find and assign the selected KYC data
      @kyc_data = @investor_kyc.kyc_datas.find(investor_kyc_params[:kyc_data_id])
      @investor_kyc.assign_kyc_data(@kyc_data, current_user)
    end

    # Determine if validation is required
    # If user is investor and entity matches, we skip validations
    skip_vaidation = current_user.curr_role_investor? && @investor_kyc.entity_id == current_user.entity_id

    # Call service to update KYC
    result = InvestorKycUpdate.call(investor_kyc: @investor_kyc, investor_user: skip_vaidation)

    respond_to do |format|
      if result.success?
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

    params.require(param_name).permit(:id, :investor_id, :entity_id, :user_id, :kyc_data_id, :kyc_type, :full_name, :birth_date, :PAN, :pan_card, :signature, :address, :corr_address, :bank_account_number, :ifsc_code, :bank_branch, :bank_account_type, :bank_name, :bank_verified, :type, :bank_verification_response, :expiry_date, :esign_emails, :bank_verification_status, :pan_verified, :pan_verification_response, :pan_verification_status, :comments, :completed_by_investor, :verified, :phone, :form_type_id, :send_kyc_form_to_user, :agreement_unit_type, :agreement_committed_amount, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end

  def commit_param
    params.require(:commit)
  end
end
