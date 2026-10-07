# frozen_string_literal: true

# @description CRUD controller for NdaConfig. Renders as a remote Bootstrap modal on the
#   Documents page via Turbo Frame. Turbo Stream responses update both the modal content and the
#   folder tree lock icon without a full page reload.
#
# Changed: Renamed from FolderNdaConfigsController, moved from core/folders/ to core/nda_configs/.
# Why: Controller now resolves a polymorphic owner from route params instead of a direct folder.
#
# @see NdaConfig
# @see NdaConfigPolicy
class NdaConfigsController < ApplicationController
  before_action :set_owner
  before_action :set_nda_config, only: %i[edit update]

  # GET /folders/:folder_id/nda_config/new
  # Changed: Added inheritance state detection to render context-appropriate modal variant.
  # Why: Module 5 introduces three NDA modes (inherit/own/opt_out). The same "new" action must
  # show different content: an info panel for inherited/opted-out folders, or the full form
  # when the folder has its own config or the GP clicks "Set Own NDA" (override param).
  # @return [void] Renders the NDA settings modal with context-appropriate content.
  def new
    @nda_config = @owner.nda_config || @owner.build_nda_config
    authorize @nda_config

    @inheritance_state = if params[:override].present?
                           "own"
                         else
                           @folder.nda_inheritance_mode
                         end
  end

  # POST /folders/:folder_id/nda_config
  # @return [void] Creates the NDA config and responds with turbo_stream to update modal and tree.
  def create
    @nda_config = @owner.build_nda_config(nda_config_params)
    @nda_config.created_by = current_user
    @nda_config.updated_by = current_user
    authorize @nda_config

    respond_to do |format|
      if @nda_config.save
        # Changed: Set folder's nda_inheritance_mode to "own" after saving config.
        # Why: Creating an NDA config means this folder now has its own NDA — it should
        # not inherit from a parent. This keeps mode and config in sync.
        @folder&.update!(nda_inheritance_mode: "own")

        # Changed: Module 9 — auto-tag the oldest approved user per investor as default signatory.
        # Why: Every investor needs at least one signatory to accept the NDA. Auto-tagging the
        #   first (oldest by InvestorAccess.created_at) approved user per investor ensures
        #   signatories exist immediately, avoiding the zero-signatory dead-end. GPs can
        #   adjust from the NDA Status Dashboard afterward.
        auto_tag_default_signatories(@nda_config)

        # Changed: Create version 1 history record on first NDA creation.
        # Why: Seeds the version history audit trail. resign_required is false
        #   because the first version has no prior acceptances to invalidate.
        create_version_record(@nda_config, resign_required: false)

        flash.now[:notice] = "NDA settings saved successfully."
        format.turbo_stream
        format.html do
          redirect_to nda_status_path(
            nda_config_id: @nda_config.id,
            folder_id: @folder&.id
          ), notice: "NDA settings saved successfully."
        end
      else
        format.turbo_stream { render :form_update, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  # GET /folders/:folder_id/nda_config/edit
  # Changed: Added @accepted_count for version bump warning in the form.
  # Why: Module 4 — when a GP selects a new PDF, the form shows a warning banner
  #   with the count of currently accepted investors who will need to re-accept.
  # @return [void] Renders the NDA settings modal with pre-filled config values.
  def edit
    authorize @nda_config
    @accepted_count = @nda_config.nda_acceptances
                                 .where(status: "accepted")
                                 .select(:investor_id)
                                 .distinct
                                 .count
  end

  # PATCH /folders/:folder_id/nda_config
  # @return [void] Updates the NDA config and responds with turbo_stream to update modal and tree.
  def update
    authorize @nda_config
    @nda_config.updated_by = current_user

    respond_to do |format|
      if @nda_config.update(nda_config_params)
        # Changed: Moved version increment from model before_save to controller.
        # Why: Shrine's cache→store promotion triggers a second save that changes
        #   nda_document_data, causing false version bumps or missed bumps in the
        #   model callback. The controller reliably detects a genuine new upload via
        #   saved_change_to_nda_document_data? (only true when the GP submitted a
        #   new file, not on Shrine promotion). Version is incremented with a direct
        #   update_column to avoid re-triggering Shrine callbacks.
        if @nda_config.saved_change_to_nda_document_data? && @nda_config.enabled?
          @nda_config.update_column(:version, @nda_config.version + 1)
          @nda_config.reload

          resign_required = ActiveModel::Type::Boolean.new.cast(
            params.dig(:nda_config, :resign_required)
          )
          resign_required = true if resign_required.nil?
          create_version_record(@nda_config, resign_required: resign_required)
          notify_version_change if resign_required
        end
        flash.now[:notice] = "NDA settings updated successfully."
        format.turbo_stream
        format.html { redirect_to @owner, notice: "NDA settings updated successfully." }
      else
        format.turbo_stream { render :form_update, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  private

  # Changed: Module 8 — sends new-version notification to LPs with stale acceptances.
  # Why: When the GP uploads a new NDA PDF, the version auto-increments. All investors
  #   who accepted an older version must re-accept. GP notification_emails get a direct
  #   mailer delivery; each stale LP user gets a Noticed notification.
  #
  # @return [void]
  def notify_version_change
    recipients = NdaNotificationRecipients.resolve(:new_version, @nda_config)
    folder_name = @nda_config.owner&.name

    # Changed: Compute previous version directly instead of dirty tracking.
    # Why: Version is now bumped via update_column (bypasses ActiveModel dirty tracking),
    #   so saved_change_to_version is nil. The old version is always current minus one.
    old_version = @nda_config.version - 1

    # Changed: Added folder_link for email CTA.
    # Why: LP needs a clickable link in the "NDA Updated" email to re-accept.
    #   Uses _url helper for absolute URL (emails can't use relative paths).
    folder_link = if @nda_config.owner.is_a?(Folder)
                    folder_documents_url(entity_id: @nda_config.entity_id, folder_id: @nda_config.owner_id)
                  end

    gp_params = {
      entity_id: @nda_config.entity_id,
      folder_name: folder_name,
      old_version: old_version,
      new_version: @nda_config.version,
      contact_email: @nda_config.contact_email,
      folder_link: folder_link
    }

    # Changed: Send directly to each GP notification email (not through Noticed).
    # Why: notification_emails are external addresses, not system Users.
    recipients[:gp_emails].each do |email|
      NdaMailer.with(gp_params.merge(direct_to: email)).nda_new_version.deliver_later
    end

    # Changed: Send LP new-version notification via Noticed.
    # Why: LP users are system Users — they get the standard Noticed pipeline with
    #   email_delay and sandbox handling.
    recipients[:lp_users].each do |user|
      NdaEventNotifier.with(
        entity_id: @nda_config.entity_id,
        email_method: :nda_new_version,
        record: @nda_config,
        folder_name: folder_name,
        old_version: old_version,
        new_version: @nda_config.version,
        contact_email: @nda_config.contact_email,
        folder_link: folder_link
      ).deliver_later(user)
    end
  rescue StandardError => e
    # Changed: Rescue notification errors to never block the update flow.
    # Why: The NDA config update is already saved — notification failure is non-critical.
    Rails.logger.error("[NdaNotification] Version change notification failed: #{e.message} (nda_config_id=#{@nda_config.id})")
  end

  # Changed: Creates a version history record after a version bump or first creation.
  # Why: Each NDA PDF upload gets a snapshot record storing the version number, Shrine file
  #   reference, resign decision, and uploader. This powers the audit trail and the conditional
  #   acceptance gate (versions with resign_required: false don't invalidate existing acceptances).
  #
  # @param nda_config [NdaConfig] The NDA config that was just saved
  # @param resign_required [Boolean] Whether this version requires existing investors to re-sign
  # @return [NdaConfigVersion, nil] The created record, or nil if creation failed
  def create_version_record(nda_config, resign_required:)
    NdaConfigVersion.create!(
      nda_config: nda_config,
      version: nda_config.version,
      nda_document_data: nda_config.nda_document_data,
      resign_required: resign_required,
      uploaded_by: current_user
    )
  rescue StandardError => e
    Rails.logger.error("[NdaVersionHistory] Version record creation failed: #{e.message} (nda_config_id=#{nda_config.id}, version=#{nda_config.version})")
    nil
  end

  # Changed: Module 9 — auto-tags the oldest approved user per investor as default NDA signatory.
  # Why: On first NDA creation, every investor needs at least one signatory so LPs are not
  #   blocked with zero signatories. Selecting the oldest approved InvestorAccess (by created_at)
  #   picks the user who has had access longest — a reasonable default. Rescue RecordNotUnique
  #   silently for idempotency if a signatory already exists (e.g. race condition on double-submit).
  #
  # @param nda_config [NdaConfig] The newly created NDA config
  # @return [void]
  def auto_tag_default_signatories(nda_config)
    InvestorAccess
      .where(entity_id: nda_config.entity_id, approved: true)
      .order(:created_at)
      .group_by(&:investor_id)
      .each_value do |accesses|
        oldest = accesses.first
        NdaSignatory.create!(
          nda_config: nda_config,
          user_id: oldest.user_id,
          tagged_by: current_user
        )
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        next
      end
  end

  # @return [void] Resolves the polymorphic owner from route params and verifies entity scoping.
  # Changed: set_folder → set_owner, resolves owner from folder_id (extensible for future owner types).
  # Why: Supports polymorphic NDA — currently folders, future IOs etc.
  def set_owner
    if params[:folder_id]
      @owner = Folder.find(params[:folder_id])
    else
      raise ActiveRecord::RecordNotFound, "No owner parameter provided"
    end

    # Changed: @folder kept as alias for view compatibility (tree caret updates reference @folder).
    # Why: Turbo Stream templates replace folder-specific DOM elements by @folder.id.
    @folder = @owner if @owner.is_a?(Folder)

    raise Pundit::NotAuthorizedError, "not allowed to access this resource" unless @owner.entity_id == current_user.entity_id

    # Changed: Added in_data_room? guard for folder owners.
    # Why: NDA config is only valid for Data Room folders. Without this guard, a crafted
    # request could create an NDA config on a non-Data-Room folder.
    raise Pundit::NotAuthorizedError, "NDA settings are only available for Data Room folders" if @folder && !@folder.in_data_room?
  end

  # @return [void] Loads the existing NDA config for edit/update actions.
  #   Redirects to the new action if no config exists, using the appropriate
  #   path helper for the owner type.
  def set_nda_config
    @nda_config = @owner.nda_config
    return if @nda_config

    redirect_to new_nda_config_path_for_owner
  end

  # @return [String] The new NDA config path for the current owner type.
  #   Each owner type has its own nested route; add a branch here when new
  #   owner types are routed.
  def new_nda_config_path_for_owner
    case @owner
    when Folder
      new_folder_nda_config_path(@owner)
    else
      root_path
    end
  end

  # @return [ActionController::Parameters] Permitted parameters for NDA config.
  # Changed: params key from :folder_nda_config to :nda_config.
  # Why: Model renamed from FolderNdaConfig to NdaConfig, Rails form builders use model class name.
  def nda_config_params
    params.require(:nda_config).permit(
      :enabled, :nda_document, :validity_type, :validity_days,
      :validity_date, :acceptance_method, :contact_email, :notification_emails
    )
  end
end
