class DocumentsController < ApplicationController
  include ActiveStorage::SetCurrent
  include DocumentHelper

  skip_before_action :verify_authenticity_token, :authenticate_user!, :set_current_entity, only: %i[signature_progress]
  before_action :set_document, only: %w[show update destroy edit send_for_esign fetch_esign_updates force_send_for_esign cancel_esign send_document_notification resend_for_esign show_email_list verify_accessibility run_fix]
  # Changed: Added NDA gate for LP folder access.
  # Why: Module 2 — LPs must accept an NDA before viewing NDA-protected folder contents.
  before_action :ensure_nda_accepted, only: [:folder]
  after_action :verify_authorized, except: %i[index search investor folder signature_progress approve bulk_actions download show_email_list]
  after_action :verify_policy_scoped, only: []

  def signature_progress
    # Check response  - if contains proper info then update doc esign status
    # if not then just respond with 200 OK
    EsignHelper.update_signature_progress(params)
    # Always respond with 200 OK - Expected from Digio
    render json: "Ok"
  end

  def fetch_esign_updates
    DocumentEsignUpdateJob.new.perform(@document.id, current_user.id)
    redirect_to [@document, { tab: "signatures-tab" }], notice: "Fetching Updates for eSignatures"
  end

  # GET /documents or /documents.json
  def index
    @bread_crumbs = { Documents: documents_path }
    fetch_rows

    # If card view is requested then we paginate the results
    @pagy, @documents = pagy(@documents, limit: params[:per_page]) if (params[:card_view].to_s.downcase == "true") && params[:all].blank?
    # Render the template sent via params else index
    render params[:template].presence || "index"
  end

  def folder
    if params[:folder_id].present?
      @folder = Folder.find(params[:folder_id])
      @entity = @folder.entity
      @show_steps = false

      @documents = if @folder.entity_id == current_user.entity_id
                     policy_scope(Document)
                   elsif !current_user.investor_advisor? || Pundit.policy(current_user, @folder).show? || (@folder.owner && Pundit.policy(current_user, @folder.owner).show?) || Folder.for_investor(current_user, @entity).exists?(id: @folder.id)
                     # Ensure that the IA user has access to the folder, as IAs can only access certain funds/deals etc
                     Document.for_investor(current_user, @folder.entity).not_template
                   else
                     Document.none
                   end

      @documents = if params[:no_folders].present? || (params[:show_root_docs].presence && current_user.has_cached_role?(:company_admin) && current_user.entity_id == @entity.id)
                     # if the user is company admin and viewing his own company data then the tree view wil render fullt and we fetch only the root docs
                     @documents.where(folder_id: params[:folder_id])
                   elsif params[:show_root_docs].presence
                     # if the user is an investor he should only see the tree view for the docs he has access to (no matter if he is company admin of his own company or not)
                     folder_ids = Folder.descendants_of(params[:folder_id]).pluck(:id) + [params[:folder_id].to_i]
                     @documents.where(folder_id: folder_ids)
                   else
                     @documents.joins(:folder).merge(Folder.descendants_of(params[:folder_id]))
                     # @documents = @documents.or(Document.where(folder_id: params[:folder_id]))
                   end
      # Newest docs first
      @documents = @documents.includes(:folder)
      @documents = if params[:documents_as_tags].present?
                     @documents.order(name: :asc)
                   else
                     @documents.order(id: :desc)
                   end

    else
      # Newest docs first
      @documents = Document.none
    end

    @no_folders = false
    render "index"
  end

  def verify_accessibility
    if @document.file.present?
      PdfAccessibilityCheckJob.perform_later(@document.id, current_user.id)
      redirect_to document_url(@document), notice: "PDF accessibility verification enqueued. You will receive an alert with the results shortly."
    else
      redirect_to document_url(@document), alert: "Document does not have an attached file to verify."
    end
  end

  def investor
    if params[:entity_id].present?
      @entity = Entity.find(params[:entity_id])
      @documents = Document.for_investor(current_user, @entity)
    end

    @documents = @documents.order(id: :desc)
    @show_steps, @no_folders = false
    render "index"
  end

  def search
    @entity = params[:entity_id].present? ? Entity.find(params[:entity_id]) : current_user.entity
    query = params[:query]
    if query.present?
      @documents = DocumentIndex.filter(term: { entity_id: @entity.id })
                                .query(simple_query_string: { fields: DocumentIndex::SEARCH_FIELDS,
                                                              query:, default_operator: 'and' })

      @pagy, @documents = pagy(@documents.page(params[:page]).objects)
      # @no_folders = true
      render "index"
    else
      redirect_to documents_path
    end
  end

  # GET /documents/1 or /documents/1.json
  def show
    ActiveRecord::Base.connected_to(role: :writing) do
      vb = ViewedBy.where(owner: @document, user: current_user, entity_id: @document.entity_id).first_or_initialize
      vb.count += 1
      vb.save
    end
  end

  def send_for_esign
    if @document.send_for_esign(user_id: current_user.id)
      redirect_to [@document, { tab: "signatures-tab" }], notice: "Document - #{@document.name} was queued for eSignature."
    else
      redirect_to [@document, { tab: "signatures-tab" }], notice: "Document was NOT sent for eSignature."
    end
  end

  def force_send_for_esign
    if @document.send_for_esign(force: params[:force], user_id: current_user.id)
      redirect_to [@document, { tab: "signatures-tab" }], notice: "Document - #{@document.name} was queued for eSignature."
    else
      redirect_to [@document, { tab: "signatures-tab" }], notice: "Document was NOT sent for eSignature."
    end
  end

  def resend_for_esign
    if @document.resend_for_esign?
      result = ResendDocumentForEsign.call(document: @document, user_id: current_user.id)
      if result.success?
        redirect_to [@document, { tab: "signatures-tab" }], notice: "Document - #{@document.name} was queued for eSignature."
      else
        redirect_to [@document, { tab: "signatures-tab" }], alert: "Document - #{@document.name} cannot be sent for eSignature - #{result[:errors]}"
      end
    else
      redirect_to [@document, { tab: "signatures-tab" }], alert: "Document - #{@document.name} cannot be sent for eSignature."
    end
  end

  def send_all_for_esign
    authorize(Document)
    if params[:folder_id].present?
      folder = Folder.find(params[:folder_id])
      authorize(folder, :send_for_esign?)
      EsignJob.perform_later(nil, current_user.id, folder_id: params[:folder_id])
      redirect_to request.referer, notice: "Documents under folder - #{folder.name} queued for eSignature"
    else
      redirect_to request.referer, alert: "Folder not found!"
    end
  end

  # allows to add a button to cancel esigning on document
  def cancel_esign
    eligible_for_update = true
    eligible_for_update = @document.last_status_updated_at.nil? || @document.last_status_updated_at < 900.seconds.ago if @document.entity.entity_setting.esign_provider == "Docusign"
    # update the esign status of the document before cancelling
    if @document.eligible_for_esign_update? && eligible_for_update
      EsignHelper.new(@document).update_esign_status
      @document.reload
    end
    if @document.eligible_for_esign_update?
      EsignHelper.new(@document).cancel_esign
      if @document.esign_status.casecmp?("cancelled")
        redirect_to [@document, { tab: "signatures-tab" }], alert: "Document's eSignature(s) was cancelled"
      else
        redirect_to [@document, { tab: "signatures-tab" }], alert: "Error cancelling eSignature(s)"
      end
    else
      redirect_to [@document, { tab: "signatures-tab" }], alert: "Document's eSignature(s) cannot be cancelled - status is #{@document.esign_status}"
    end
  end

  def approve
    if request.post?
      options = params.to_unsafe_h.slice(:user_id, :notification, :owner_type, :parent_folder_id)
      options[:user_id] = current_user.id

      DocumentApprovalJob.perform_later(current_user.entity_id, params[:start_date], params[:end_date], options)

      redirect_to documents_path, notice: "Document approval started, please check back in a few mins."
    end
  end

  # GET /documents/new
  def new
    @document = Document.new(document_params)
    @bread_crumbs = { Documents: documents_path }
    @bread_crumbs[@document.owner.to_s] = polymorphic_path(@document.owner) if @document.owner.present?
    @bread_crumbs[:New] = nil

    @document.setup_folder_defaults
    setup_custom_fields(@document)
    authorize @document
  end

  # GET /documents/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    setup_custom_fields(@document)
  end

  # POST /documents or /documents.json
  def create
    @document = Document.new(document_params.except(:e_signatures_attributes))
    @document.entity_id = @document.owner&.entity_id || current_user.entity_id
    @document.user_id = current_user.id

    # SECURITY (finding H7): a document cannot be self-approved at creation — approval is granted
    # later via the approver-gated flow. And only company admins may publish a document
    # (public_visibility); reset it for anyone else. entity_id is set above, so the policy check
    # evaluates against the correct entity.
    @document.approved = false
    @document.approved_by_id = nil
    @document.public_visibility = false unless policy(@document).set_public_visibility?

    authorize @document

    respond_to do |format|
      ActiveRecord::Base.transaction do
        if @document.save
          # Create e-signatures after document is saved
          if document_params[:e_signatures_attributes].present?
            document_params[:e_signatures_attributes].each_value do |signature_attrs|
              next if signature_attrs['_destroy'] == 'true'

              @document.e_signatures.create!(
                label: signature_attrs['label'],
                signature_type: signature_attrs['signature_type'],
                notes: signature_attrs['notes']
              )
            end
          end

          format.html { save_and_upload }
          format.json { render :show, status: :created, location: @document }
        else
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @document.errors, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      @document.errors.add(:base, "Failed to create signatures: #{e.message}")
      format.html { render :new, status: :unprocessable_entity }
      format.json { render json: @document.errors, status: :unprocessable_entity }
    end
  end

  def download
    rows = fetch_rows
    DocumentDownloadJob.perform_later(params[:folder_id], current_user.id, document_ids: rows.pluck(:id))
    redirect_to params[:back_to], notice: "You will be sent a download link for the documents in a few minutes."
  end

  # PATCH/PUT /documents/1 or /documents/1.json
  def update
    # SECURITY (finding H7): approval and public visibility are privileged and were previously
    # settable by plain mass assignment, letting any user with update? self-approve (bypassing the
    # approver workflow) or publish a document. Apply them here with their own authorization.
    apply_privileged_document_attrs!

    # Not for general consumption: the _form only shows this field when
    # document.template? && params[:debug].present?, but that's UI-only -- anyone with
    # ordinary update? rights on a template could otherwise PATCH pdf_conversion_engine
    # directly. Gate it server-side the same way, same pattern as the H7 attrs above.
    apply_pdf_conversion_engine!

    respond_to do |format|
      # SECURITY (finding H6): strip entity_id so an existing document cannot be relocated to
      # another tenant via mass assignment. entity_id is set once at #create (owner-derived) and
      # is immutable thereafter. NOTE: this only affects documents_controller — the portfolio
      # company's KPI magic-link upload uses nested documents_attributes (Document::NESTED_ATTRIBUTES)
      # on kpi_reports#update, a separate path that is intentionally left unchanged.
      # H7: approved/approved_by_id/public_visibility are applied above (gated), never mass-assigned.
      # pdf_conversion_engine is applied above (gated), never mass-assigned.
      journey_started_at = Time.current
      if @document.update(document_params.except(:entity_id, :approved, :approved_by_id, :public_visibility, :pdf_conversion_engine))
        evaluate_journey_if_notice_unapproved(journey_started_at)
        evaluate_journey_if_notice_approved
        format.html { save_and_upload }
        format.json { render :show, status: :ok, location: @document }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @document.errors, status: :unprocessable_entity }
      end
    end
  end

  def save_and_upload
    if params[:commit] == "Save & Upload More"
      fields = %w[entity_id owner_id owner_type description owner_tag orignal download printing]
      dup = @document.duplicate(fields)
      redirect_to new_document_url({ document: dup.attributes.slice(*fields) }), notice: "Document #{@document.name} was successfully saved. Please upload new document below."
    elsif params[:redirect_to].present?
      redirect_to params[:redirect_to], notice: "Document was successfully saved."
    elsif @document.owner
      redirect_to polymorphic_url(@document.owner, tab: "docs-tab", format: :html), notice: "Document was successfully saved."
    else
      redirect_to document_url(@document), notice: "Document was successfully saved."
    end
  end

  # DELETE /documents/1 or /documents/1.json
  def destroy
    @document.destroy

    respond_to do |format|
      format.html do
        if @document.owner
          redirect_to [@document.owner, { tab: "docs-tab" }], notice: "Document was successfully deleted."
        else
          redirect_to documents_url, notice: "Document was successfully deleted."
        end
      end
      format.json { head :no_content }
    end
  end

  def send_document_notification
    DocumentSender.send(@document, current_user.id, params[:custom_notification_id])

    redirect_to document_url(@document), notice: "Document will be sent to the email addresses as requested."
  rescue StandardError => e
    redirect_to document_url(@document), alert: e.message
  end

  # AI "Fix Me": kicks off TemplateFixAgent against this template document with
  # the user-described problem. Runs in the background — TemplateFixJob sends
  # a UserAlert when the resulting draft (or failure) is ready.
  def run_fix
    issue_description = params[:issue_description].to_s.strip
    if issue_description.blank?
      redirect_to document_url(@document), alert: "Please describe the issue before running Fix Me."
      return
    end

    support_agent = SupportAgent.find_or_create_by!(entity_id: current_user.entity_id, agent_type: "TemplateFixAgent") do |sa|
      sa.name = "Template Fix Agent"
      sa.category = "Ops"
      sa.llm_model = "gemini-3.7-flash"
      sa.enabled = true
    end

    TemplateFixJob.perform_later(
      support_agent_id: support_agent.id,
      document_id: @document.id,
      issue_description: issue_description,
      llm_model: params[:llm_model].presence,
      user_id: current_user.id
    )

    redirect_to document_url(@document), notice: "Fix Me is running in the background — you'll get a notification when it's done."
  end

  def share_by_email
    authorize @document, :share_by_email? # Authorize the action
    result = DocShareCreationService.wtf?(document: @document, emails: document_params[:emails], user_id: current_user.id)

    if result.success?
      redirect_to document_url(@document), notice: "Document shared successfully with selected emails."
    else
      redirect_to document_url(@document), alert: "Failed to share document: #{result.errors}"
    end
  end

  # One row per email that will actually go out, not per person: the same contact appears once
  # for each stakeholder they represent, because each of those emails carries a different cc
  # list. See docs/modules/notifications/document_notification_cc_resolution.md.
  def show_email_list
    @notification_recipients = @document.notification_recipients
  end

  # WithBulkActions#bulk_actions, plus a marker for the page it redirects back to: an approver sent
  # here by a journey's "Approve notices" step sees "approval started — close this tab" instead of
  # the "these still need approval" banner while the job runs (documents/_approval_hint).
  def bulk_actions
    super
    flash[:bulk_approve_started] = true if params[:bulk_action].to_s.casecmp?("approve")
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_document
    @document = Document.find(params[:id])
    authorize @document
    @bread_crumbs = { Documents: documents_path }
    @bread_crumbs[@document.owner.to_s] = polymorphic_path(@document.owner) if @document.owner.present?
    @bread_crumbs[@document.name.to_s] = document_path(@document)
  end

  def entity_documents
    # We are trying to get documents that belong to some entity
    @entity = Entity.find(params[:entity_id])
    # Show all the documents for the investor for that entity
    @documents = Document.entity_documents(current_user, @entity.id)
  end

  def owner_documents
    # We are trying to get documents that belong to some entity
    @owner = nil
    if params[:owner_type].present? && params[:owner_id].present?
      # Show all the documents for the owner for that entity
      @owner = params[:owner_type].constantize.find(params[:owner_id])
      @entity = @owner.entity

      @documents = if policy(@owner).show?
                     Document.owner_documents(@owner)
                   else
                     Document.none
                   end
    end
    @show_steps = false
  end

  # Used for bulk actions and index
  def fetch_rows
    if params[:owner_id].present? && params[:owner_type].present?
      # This is typicaly for investors to view documents of a sale, offer, commitment etc
      owner_documents
    else
      # See your own docs
      @entity = current_user.entity
      @q = Document.ransack(params[:q])
      @documents = policy_scope(@q.result)
      authorize(Document)
    end

    if params[:folder_id].present?
      @folder = Folder.find(params[:folder_id])
      # in widgers card view if we only want to see the docs in the folder and not the subfolders then we send include_sub_folders as false
      @documents = if params[:include_sub_folders].to_s.downcase == "false"
                     @documents.where(folder_id: params[:folder_id])
                   else
                     @documents.joins(:folder).merge(Folder.subtree_of(params[:folder_id]))
                   end
    end

    # Filter by owner_tag
    @documents = filter_params(@documents, :entity_id, :owner_id, :owner_type, :import_upload_id, :owner_tag)
    # This is specifically for non company_admins
    @documents = @documents.where(user_id: current_user.id) unless current_user.has_cached_role?(:company_admin)

    # Newest docs first
    @documents = @documents.includes(:folder).order(id: :desc)
    @documents
  end

  # Only allow a list of trusted parameters through.
  # SECURITY (finding H7): applies the privileged document attributes (approval + public
  # visibility) that must never be mass-assigned. Each change is authorized on its own and only
  # when the value actually changes, so an ordinary edit that merely re-submits an unchanged
  # public_visibility checkbox is not blocked for non-privileged editors. approved_by_id is always
  # set server-side, never trusted from the client. Raises Pundit::NotAuthorizedError otherwise.
  def apply_privileged_document_attrs!
    bool = ActiveModel::Type::Boolean.new

    if document_params.key?(:approved)
      approving = bool.cast(document_params[:approved])
      if approving != @document.approved
        authorize @document, approving ? :approve? : :unapprove?
        @document.approved = approving
        @document.approved_by_id = approving ? current_user.id : nil
      end
    end

    if document_params.key?(:public_visibility)
      make_public = bool.cast(document_params[:public_visibility])
      if make_public != @document.public_visibility
        authorize @document, :set_public_visibility?
        @document.public_visibility = make_public
      end
    end
  end

  # Internal debugging knob (docs/modules/documents/m365_graph_pdf_conversion.md,
  # docs/modules/documents/google_docs_pdf_conversion.md), not a feature for general editors: only
  # settable on a document that is already a template, and only when the request explicitly
  # carries params[:debug] -- mirrors the same gate the form field itself is rendered behind,
  # enforced here since the form-level gate alone is not a security boundary.
  def apply_pdf_conversion_engine!
    return unless document_params.key?(:pdf_conversion_engine)
    return unless @document.template? && params[:debug].present?

    @document.pdf_conversion_engine = document_params[:pdf_conversion_engine]
  end

  def document_params
    params.require(:document).permit(:name, :text, :entity_id, :video, :form_type_id, :tag_list, :template, :template_docs_to_append,
                                     :pdf_conversion_engine,
                                     :signature_enabled, :public_visibility, :send_email, :display_on_page, :embed,
                                     :download, :printing, :orignal, :owner_id, :owner_type, :owner_tag, :approved, :approved_by_id,
                                     :tag_list, :folder_id, :file, :force_esign_order, :as_of, properties: {}, e_signatures_attributes: %i[id user_id label signature_type notes _destroy], stamp_papers_attributes: %i[id tags sign_on_page notes note_on_page _destroy], emails: [])
  end

  # @return [void] NDA gate — redirects LP to acceptance screen if folder has an active NDA
  #   that the user has not yet accepted at the current version, or whose acceptance has expired.
  # Gate order: GP bypass → investor_ids lookup → exemption check (by investor_id) →
  #   stakeholder acceptance → version match → time expiry → pass.
  # Exemption is checked by investor_id, not user_id, so that if ANY InvestorAccess record
  #   for the user's investor is exempt, all users under that investor bypass the gate.
  # @see InvestorAccess#exempt_from_nda
  def ensure_nda_accepted
    return if params[:folder_id].blank?

    @folder ||= Folder.find(params[:folder_id])

    return unless @folder.in_data_room?
    return if @folder.entity_id == current_user.entity_id

    nda_config = @folder.effective_nda_config
    return if nda_config.nil?
    return unless nda_config.enabled?

    investor_ids = InvestorAccess
                   .where(user_id: current_user.id, entity_id: nda_config.entity_id, approved: true)
                   .pluck(:investor_id)

    return if investor_ids.empty?

    # Stakeholder-level exemption — checks by investor_id so all users under an exempt
    # investor bypass the gate, even if the exempt flag is on a different user's record.
    return if InvestorAccess.exists?(investor_id: investor_ids, entity_id: nda_config.entity_id, approved: true, exempt_from_nda: true)

    latest = NdaAcceptance
             .where(nda_config_id: nda_config.id, investor_id: investor_ids)
             .order(created_at: :desc)
             .limit(1)
             .first

    return if latest&.accepted?

    nda_url = nda_acceptances_path(
      nda_config_id: nda_config.id,
      folder_id: @folder.id,
      return_to: request.fullpath
    )

    # Changed: Simple redirect for both regular and Turbo Frame requests.
    # Why: The NDA acceptance views wrap content in a turbo_frame_tag "documents_frame",
    #   so Turbo Frame requests render the acceptance screen inside the right pane naturally.
    #   No need for inline JS breakout — the frame stays intact with sidebar/topbar visible.
    redirect_to nda_url
  end

  # @param path [String, nil] The return_to path from params.
  # @return [String] A validated relative path, or the data rooms fallback.
  #   Rejects nil, empty, external URLs, and protocol-relative URLs to prevent open redirects.
  def safe_return_to(path)
    return data_rooms_folders_path if path.blank?
    return data_rooms_folders_path unless path.start_with?("/")
    return data_rooms_folders_path if path.start_with?("//")
    return data_rooms_folders_path if path.include?("://")

    path
  end

  # Approving a generated notice moves its call's or distribution's journey on (real time; no-op
  # without a journey); unapproving one is an undoing action for that journey.
  # Worked examples E7, E10, J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # Worked examples E12 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def evaluate_journey_if_notice_approved
    return unless @document.saved_change_to_approved? && @document.approved

    @document.notice_journey_record&.journey_progress!(actor: current_user)
  end

  def evaluate_journey_if_notice_unapproved(started_at)
    return unless @document.saved_change_to_approved? && !@document.approved

    @document.notice_journey_record&.journey_undo_evaluate(note: "Notice unapproved by #{current_user.full_name}",
                                                           actor: current_user, started_at:)
  end
end
# rubocop:enable Metrics/ClassLength
