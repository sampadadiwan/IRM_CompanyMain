class InvestorKycsController < ApplicationController
  include WithCustomFieldFilter
  include HasWorkflowable
  include WithJourneyPanel # show's journey evaluation and the journey action (investor-kyc-journey)

  helper InvestorKycAnalyticsHelper
  after_action :verify_policy_scoped, only: [:index] # add send_reminder_to_all?

  # Allow unauthenticated investors to access their KYC via a signed magic link.
  skip_before_action :authenticate_user!, only: %i[show edit update extract_docs_data doc_first_upload processing], if: -> { params[:signed_id].present? }

  before_action :set_investor_kyc, only: %i[show journey edit update destroy toggle_verified generate_docs generate_new_aml_report override_aml_status send_kyc_reminder notify_kyc_required send_notification validate_docs_with_ai extract_docs_data preview download_kra_data fetch_ckyc_data assign_kyc_data edit_reporting_fields update_reporting_fields request_updates processing doc_first_upload]
  before_action :set_workflowable, only: [:show] # runs after set_investor_kyc so @investor_kyc is available
  after_action :verify_authorized, except: %i[index search generate_all_docs edit_my_kyc investor_pending]

  has_scope :uncalled, type: :boolean
  has_scope :unverified, type: :boolean
  has_scope :agreement_uncalled, type: :boolean
  has_scope :agreement_overcalled, type: :boolean

  # GET /investor_kycs or /investor_kycs.json
  def index
    @bread_crumbs = { KYCs: investor_kycs_path }
    fetch_rows

    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json
    end
  end

  def analytics
    authorize(InvestorKyc)
    fetch_rows
    render "investor_kycs/analytics_content", layout: false
  end

  def fetch_rows
    authorize(InvestorKyc)

    result = InvestorKycList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = result.q
    @investor_kycs = result.investor_kycs

    @investor = Investor.find(params[:investor_id]) if params[:investor_id].present?

    @all_investor_kycs = @investor_kycs
    @pagy, @investor_kycs = pagy(@investor_kycs, limit: params[:per_page]) if params[:all].blank? && !request.format.xlsx?

    @investor_kycs
  end

  # GET /investor_kycs/1 or /investor_kycs/1.json
  # Fund users see the KYC journey (step bar + what's needed now), evaluated on every view so it is
  # always current. Investors — logged in or on the emailed link (no current_user) — never do.
  # Worked examples H2, X1 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def show
    @journey = evaluate_journey(@investor_kyc) if current_user && !current_user.curr_role_investor?
  end

  # GET /investor_kycs/:id/journey — just the journey panel, for the frame a real-time update inserts.
  # Authorized as journey? (= show?), entity-scoped by InvestorKycPolicy.
  # Worked examples E15, X5 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def journey
    return head(:forbidden) if current_user.curr_role_investor?

    render_journey_panel(@investor_kyc)
  end

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

  # POST /investor_kycs/:id/extract_docs_data
  # Runs KycDocExtractorAgent inline against the uploaded documents and
  # pre-populates KYC fields. Returns a Turbo Stream that refreshes the form.
  def extract_docs_data
    authorize(@investor_kyc)

    agent = @investor_kyc.entity.agents.find_by(agent_type: "KycDocExtractorAgent", enabled: true)

    unless agent
      return redirect_to edit_investor_kyc_url(@investor_kyc, signed_id: params[:signed_id]),
                         alert: "Document extractor agent is not configured for this entity."
    end

    started_at = Time.current
    result = KycDocExtractorAgent.call(
      support_agent_id: agent.id,
      target: @investor_kyc
    )
    # Extraction rewrites the KYC's details; after "Review KYC" that is an edit like any other.
    # The investor's own documents-first path happens before submission, so there is nothing to undo.
    # Worked examples E12, E14 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    if current_user && !current_user.curr_role_investor?
      @investor_kyc.journey_invalidate(check_keys: "investor_kyc.review_kyc", reason: "KYC details changed after review",
                                       actor: current_user, only_if_passed: "investor_kyc.review_kyc")
      @investor_kyc.journey_undo_evaluate(note: "KYC details changed after review", started_at:, actor: current_user)
    end

    extracted = result[:results]&.count { |r| r[:status] == :extracted } || 0
    skipped   = result[:results]&.count { |r| r[:status] == :skipped }   || 0
    errors    = result[:results]&.count { |r| r[:status] == :error }     || 0

    notice = "Extracted #{extracted} field(s) from your documents."
    notice += " #{skipped} skipped (already filled or document not uploaded)." if skipped.positive?
    notice += " #{errors} error(s) — check server logs." if errors.positive?

    redirect_to edit_investor_kyc_url(@investor_kyc, signed_id: params[:signed_id]), notice: notice
  end

  # GET /investor_kycs/new
  def new
    kyc_type = investor_kyc_params[:kyc_type] || "Individual"

    # Create the appropriate KYC type based on the kyc_type parameter
    @investor_kyc = kyc_type == "Individual" ? IndividualKyc.new(investor_kyc_params) : NonIndividualKyc.new(investor_kyc_params)
    @investor_kyc.entity_id ||= current_user&.entity_id # needed for Pundit belongs_to_entity? check
    @investor_kyc.type = @investor_kyc.type_from_kyc_type

    @bread_crumbs = { KYCs: investor_kycs_path }
    @bread_crumbs[@investor_kyc.investor.investor_name.to_s] = investor_path(@investor_kyc.investor) if @investor_kyc.investor.present?
    @bread_crumbs[:New] = nil

    # If the investor is present, set the full_name to the investor's name
    @investor_kyc.full_name = @investor_kyc.investor.investor_name if @investor_kyc.investor.present? && @investor_kyc.individual?
    authorize(@investor_kyc)

    # Set up custom fields for the KYC model. Sometimes we need to force the form type based on the form_type_id parameter
    form_type = current_user.entity.form_types.where(id: investor_kyc_params[:form_type_id]).last
    setup_custom_fields(@investor_kyc, type: @investor_kyc.type, force_form_type: form_type)
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

  # GET /investor_kycs/:id/processing
  # Holding page shown while KycDocExtractorJob runs in the background.
  # The job broadcasts a Turbo Stream that triggers client-side redirect to edit.
  def processing
    authorize @investor_kyc
    # Read (and clear) the marker KycDocExtractorJob writes to Redis when it finishes.
    redirect_url = KycDocExtractorJob.consume_redirect(@investor_kyc.id)

    respond_to do |format|
      # First load: if the job already finished (always so with the inline adapter in test),
      # skip the spinner entirely.
      format.html { redirect_to redirect_url if redirect_url.present? }
      # Polled by the spinner page (processing_poll_controller.js) as a fallback for a
      # missed Turbo Stream broadcast; redirect_url stays null until the job is done.
      format.json { render json: { redirect_url: redirect_url } }
    end
  end

  # PATCH /investor_kycs/:id/doc_first_upload
  # Accepts uploaded documents for an existing KYC (investor magic link path), enqueues
  # the extraction job, then redirects through the processing spinner page.
  def doc_first_upload
    authorize @investor_kyc
    @investor_kyc.assign_attributes(doc_first_upload_params)
    kyc_folder = @investor_kyc.document_folder
    # save(validate: false) skips before_validation callbacks including Document#setup_folder,
    # so folder_id (NOT NULL) would never be set on new documents. Set it explicitly here.
    @investor_kyc.documents.each do |doc|
      doc.entity_id ||= @investor_kyc.entity_id
      doc.folder    ||= kyc_folder if doc.new_record?
    end
    @investor_kyc.save(validate: false)
    redirect_to doc_first_next_url(@investor_kyc, signed_id: params[:signed_id])
  end

  # GET /investor_kycs/1/edit
  def edit
    investor_facing = pundit_user&.curr_role_investor? || params[:signed_id].present?
    kyc_locked      = @investor_kyc.submission_completed? || @investor_kyc.submission_verified?
    if investor_facing && kyc_locked
      return redirect_to investor_kyc_url(@investor_kyc, signed_id: params[:signed_id]),
                         alert: "This KYC has already been submitted and cannot be edited."
    end

    # Doc-first wizard for investors: when the entity has kyc_doc_first_wizard enabled,
    # an active KycDocExtractorAgent, the investor has not yet uploaded any documents,
    # and the KYC hasn't been through extraction, show the doc upload form first.
    return render :doc_first_for_edit if doc_first_wizard_for_edit?

    @bread_crumbs[:Edit] = nil
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
    # We get this param validate to decide whether to validate or not, if the investor is doing an interim save validate is false, and he will complete the form later.
    validate = params[:validate].present? ? params[:validate] != "false" : investor_user

    # Doc-first wizard: skip validations for the shell, run extraction, then go to edit.
    doc_first = params[:doc_first] == "true"
    validate = false if doc_first

    @investor_kyc.documents.each(&:validate)

    respond_to do |format|
      if InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user:, validate:, owner_id: params[:owner_id], owner_type: params[:owner_type]).success?
        if doc_first
          format.html { redirect_to doc_first_next_url(@investor_kyc) }
        else
          format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Investor kyc was successfully saved." }
          format.json { render :show, status: :created, location: @investor_kyc }
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: result[:errors], status: :unprocessable_entity }
      end
    end
  end

  def send_kyc_reminder
    if @investor_kyc.investor.approved_users.present?
      @investor_kyc.send_kyc_form(reminder: true, custom_notification_id: params[:custom_notification_id])
      msg = "KYC Reminder sent successfully."
      redirect_to investor_kyc_url(@investor_kyc), notice: msg
    else
      msg = "KYC Reminder could not be sent as no user has been assigned to the investor."
      redirect_to investor_kyc_url(@investor_kyc), alert: msg
    end
  end

  def notify_kyc_required
    if @investor_kyc.investor.approved_users.present?
      # Set the flag to true to indicate that the KYC form should be sent
      @investor_kyc.send_kyc_form_to_user = true
      # If a custom notification ID is provided, use it to send the KYC form
      @investor_kyc.send_kyc_form(custom_notification_id: params[:custom_notification_id])
      # Redirect to the KYC page with a success message
      msg = "KYC form sent successfully."
      redirect_to investor_kyc_url(@investor_kyc), notice: msg
    else
      msg = "KYC form could not be sent as no user has been assigned to the investor."
      redirect_to investor_kyc_url(@investor_kyc), alert: msg
    end
  end

  def send_notification
    authorize @investor_kyc
    @investor_kyc.updates_requested_notification(msg: params[:message])
    redirect_to investor_kyc_url(@investor_kyc), notice: "Notification sent successfully. Please wait for us to respond to your request."
  end

  def send_kyc_reminder_to_all
    entity_id = current_user.entity_id
    @investor_kycs = policy_scope(InvestorKyc)
    authorize(InvestorKyc)

    @investor_kycs.where(entity_id:, verified: false)
                  .where.not(submission_status: %w[completed verified])
                  .find_each do |kyc|
      kyc.send_kyc_form(reminder: true, custom_notification_id: params[:custom_notification_id])
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
    acting_user = current_user || @signed_id_user
    investor_user = acting_user&.curr_role_investor? || @signed_id_user.present?
    validate = params[:validate].present? ? params[:validate] != "false" : investor_user

    was_already_completed = @investor_kyc.submission_completed? || @investor_kyc.submission_verified?
    og_submission_status = @investor_kyc.submission_status
    og_submitted_at = @investor_kyc.submitted_at
    # Guard: investors cannot update a completed/verified KYC (per PRD — fund admin is exempt).
    if was_already_completed && investor_user
      return redirect_to investor_kyc_url(@investor_kyc, signed_id: params[:signed_id]),
                         alert: "This KYC has already been submitted and cannot be edited."
    end
    status_attrs = resolve_status_transition(params[:submit_action], investor_user:)

    @investor_kyc.assign_attributes(investor_kyc_params.merge(status_attrs))
    existing_docs = @investor_kyc.documents.select(&:persisted?)
    if existing_docs.any?
      ActiveRecord::Associations::Preloader.new(
        records: existing_docs,
        associations: %i[folder entity user form_type e_signatures stamp_papers]
      ).call
    end
    @investor_kyc.documents.each(&:validate)

    respond_to do |format|
      if InvestorKycUpdate.call(investor_kyc: @investor_kyc, investor_user:, validate:).success?
        notify_fund_on_submission(@investor_kyc) if status_attrs[:submission_status] == "completed" && !was_already_completed
        notice = status_attrs[:submission_status] == "completed" ? "KYC submitted. The fund team has been notified." : "Investor kyc was successfully saved."
        status_attrs[:submission_status]
        format.html do
          redirect_to investor_kyc_url(@investor_kyc, signed_id: params[:signed_id]),
                      notice: notice
        end
        format.json { render :show, status: :ok, location: @investor_kyc }
      else
        @investor_kyc.submission_status = og_submission_status
        @investor_kyc.submitted_at = og_submitted_at
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /investor_kycs/:id/request_updates
  # Fund admin requests investor to re-fill. Sends a fresh magic link with an optional message.
  def request_updates
    authorize(@investor_kyc)
    # Taken before the KYC changes, so the review and sign-offs given before the request are reset
    started_at = Time.current
    @investor_kyc.update_columns(
      submission_status: "link_sent",
      link_sent_at: Time.current,
      completed_by_investor: false,
      submitted_at: nil
    )
    # rubocop:enable Rails/SkipsModelValidations
    # update_columns skips callbacks: move the journey back to "Submit KYC" explicitly
    # Worked examples E10 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    @investor_kyc.journey_undo_evaluate(note: "Updates requested", started_at:, actor: current_user)
    msg = params[:message].presence
    @investor_kyc.investor.notification_users(with_tag: 'KYC').each do |user|
      InvestorKycNotifier.with(
        record: @investor_kyc,
        entity_id: @investor_kyc.entity_id,
        email_method: :notify_updates_requested,
        msg: msg,
        user_id: user.id
      ).deliver_later(user)
    end
    redirect_to investor_kyc_url(@investor_kyc), notice: "Update request sent to investor with a fresh link."
  end

  # GET /investor_kycs/investor_pending
  # Dashboard for logged-in investors showing outstanding KYC requests.
  def investor_pending
    authorize InvestorKyc, :investor_pending?
    @investor_kycs = InvestorKyc
                     .pending_investor
                     .for_investor(current_user)
                     .includes(:entity, :investor)
    @bread_crumbs = { 'Pending KYC Requests': investor_pending_investor_kycs_path }
  end

  # GET /investor_kycs/1/edit_reporting_fields
  # This action is used to edit the reporting fields of an InvestorKyc
  # It renders a form for updating the reporting fields, which are custom fields associated with the KYC
  def edit_reporting_fields
    authorize(@investor_kyc)
    url = update_reporting_fields_investor_kyc_path(@investor_kyc)
    render "form_custom_fields/reporting_fields_form", locals: { object: @investor_kyc, url: url }
  end

  # PUT /investor_kycs/1/update_reporting_fields
  # This action updates the reporting fields of an InvestorKyc and nothing else
  def update_reporting_fields
    investor_user = current_user.curr_role_investor?
    @investor_kyc.json_fields.merge!(investor_kyc_params["properties"] || {})

    respond_to do |format|
      if @investor_kyc.save(validate: investor_user)
        format.html { redirect_to investor_kyc_url(@investor_kyc), notice: "Reporting Fields updated successfully." }
        format.json { render :show, status: :ok, location: @investor_kyc }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: result[:errors], status: :unprocessable_entity }
      end
    end
  end

  def toggle_verified
    investor_user = current_user.curr_role_investor?
    new_verified = !@investor_kyc.verified
    new_status   = new_verified ? "verified" : "completed"
    @investor_kyc.assign_attributes(
      verified: new_verified,
      verified_by_id: new_verified ? current_user.id : nil,
      submission_status: new_status
    )
    status = new_verified ? "verified" : "unverified"

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

      if params[:document_template_ids].present? && Date.local_parse(params[:start_date]) <= Date.local_parse(params[:end_date])
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
      if params[:document_template_ids].present? && Date.local_parse(params[:start_date]) <= Date.local_parse(params[:end_date])
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

  def override_aml_status
    authorize(@investor_kyc)
    new_status = params[:aml_status]
    reason = params[:aml_override_reason].to_s.strip

    if InvestorKyc::AML_STATUSES.exclude?(new_status) || reason.blank?
      redirect_to(investor_kyc_url(@investor_kyc), alert: "Please select a status and provide a reason for the override.")
      return
    end

    started_at = Time.current
    @investor_kyc.override_aml_status!(status: new_status, reason:)
    # Cleared → "Clear AML match" done; confirmed as a match → it moves back there
    # Worked examples H10 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    if new_status == "potential_match"
      @investor_kyc.journey_undo_evaluate(note: "AML match confirmed", started_at:, actor: current_user)
    else
      @investor_kyc.journey_progress!(actor: current_user)
    end
    redirect_to investor_kyc_url(@investor_kyc), notice: "AML status overridden."
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
    if params[:signed_id].present?
      find_by_signed_id_for_user(params[:signed_id])
      unless @investor_kyc
        render inline: <<~HTML, layout: false, status: :gone
          <!DOCTYPE html><html><body>
          <div style="font-family:sans-serif;max-width:600px;margin:4rem auto;padding:1rem">
            <h4>This link has expired or is invalid</h4>
            <p>Please contact your fund manager to request a new invitation link.</p>
          </div>
          </body></html>
        HTML
        return
      end
    end
    @investor_kyc ||= InvestorKyc.find(params[:id])
    authorize(@investor_kyc)
    @bread_crumbs = { KYCs: investor_kycs_path }
    @bread_crumbs[@investor_kyc.investor.investor_name.to_s] = investor_path(@investor_kyc.investor) if @investor_kyc.investor.present?
    @bread_crumbs[@investor_kyc.full_name.to_s] = investor_kyc_path(@investor_kyc)
  end

  # Pundit uses this method to determine the authorizing user.
  # When a signed magic link is used, @signed_id_user is the investor extracted
  # from the token — use them instead of current_user (which is nil for unauthenticated requests).
  def pundit_user
    @signed_id_user || current_user
  end

  # Where to send the user after a doc-first upload. Only go through the processing spinner
  # when an extraction job was actually enqueued: with no enabled KycDocExtractorAgent no job
  # runs, nothing ever marks extraction done, and the spinner would wait forever.
  def doc_first_next_url(investor_kyc, signed_id: nil)
    signed_id = signed_id.presence

    # Submitted with no files: there is nothing to extract, so skip the job and the spinner and
    # return to the upload form. exists? queries the DB, so blank entries never saved don't count.
    unless investor_kyc.documents.exists?
      flash[:alert] = "Upload at least one document, or choose Fill Form Manually."
      return edit_investor_kyc_url(investor_kyc, signed_id:)
    end

    if enqueue_doc_extraction_for(investor_kyc, signed_id:)
      processing_investor_kyc_url(investor_kyc, signed_id:)
    else
      # skip_doc_first stops the edit page from showing the upload wizard again.
      edit_investor_kyc_url(investor_kyc, skip_doc_first: 1, signed_id:)
    end
  end

  # Enqueues KycDocExtractorJob; returns false (and enqueues nothing) when the entity has
  # no enabled KycDocExtractorAgent.
  def enqueue_doc_extraction_for(investor_kyc, signed_id: nil)
    agent = investor_kyc.entity.agents.find_by(agent_type: "KycDocExtractorAgent", enabled: true)
    return false unless agent

    redirect_url = edit_investor_kyc_url(investor_kyc, doc_first_done: 1, signed_id: signed_id.presence)
    # Clear any unconsumed marker from an earlier run before this run can write its own.
    KycDocExtractorJob.clear_redirect(investor_kyc.id)
    KycDocExtractorJob.perform_later(investor_kyc.id, agent.id, redirect_url)
    true
  end

  # Returns true when the doc-first upload form should be shown instead of the regular KYC edit form.
  def doc_first_wizard_for_edit?
    return false if params[:skip_doc_first].present?
    # Extraction has already run for this upload; going back to the upload form would loop.
    return false if params[:doc_first_done].present?
    return false if @investor_kyc.submission_completed? || @investor_kyc.submission_verified?
    return false unless @investor_kyc.entity.entity_setting.kyc_doc_first_wizard?
    return false unless @investor_kyc.entity.support_agents.kyc_doc_extractor_agent?

    # Only show the upload form when no documents have been attached yet.
    @investor_kyc.documents.empty?
  end

  # Accepts only the documents nested attributes from the doc-first upload form.
  # The param key depends on the KYC subtype (IndividualKyc → :individual_kyc, etc.)
  def doc_first_upload_params
    param_name = if params[:individual_kyc].present?
                   :individual_kyc
                 elsif params[:non_individual_kyc].present?
                   :non_individual_kyc
                 else
                   :investor_kyc
                 end
    return ActionController::Parameters.new.permit! if params[param_name].blank?

    params.require(param_name).permit(documents_attributes: Document::NESTED_ATTRIBUTES)
  end

  def resolve_status_transition(submit_action, investor_user:)
    if submit_action == "final"
      { submission_status: "completed", submitted_at: Time.current }
    elsif investor_user && (@investor_kyc.submission_not_sent? || @investor_kyc.submission_link_sent?)
      { submission_status: "draft_saved" }
    else
      {}
    end
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

    return ActionController::Parameters.new.permit! if params[param_name].blank?

    params.require(param_name).permit(:id, :investor_id, :entity_id, :user_id, :kyc_data_id, :kyc_type, :full_name, :birth_date, :PAN, :pan_card, :signature, :address, :corr_address, :bank_account_number, :ifsc_code, :bank_branch, :bank_account_type, :bank_name, :bank_verified, :type, :bank_verification_response, :expiry_date, :esign_emails, :bank_verification_status, :pan_verified, :pan_verification_response, :pan_verification_status, :comments, :completed_by_investor, :verified, :phone, :form_type_id, :send_kyc_form_to_user, :agreement_unit_type, :agreement_committed_amount, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end

  def commit_param
    params.require(:commit)
  end

  def notify_fund_on_submission(investor_kyc)
    recipients = investor_kyc.entity.employees.active.select { |e| e.enable_kycs && !e.investor_advisor? }
    recipients.each do |employee|
      InvestorKycNotifier.with(
        record: investor_kyc,
        entity_id: investor_kyc.entity_id,
        email_method: :notify_kyc_submitted,
        msg: "KYC submitted by investor: #{investor_kyc.full_name}",
        user_id: employee.id
      ).deliver_later(employee)
    end
  end
end
