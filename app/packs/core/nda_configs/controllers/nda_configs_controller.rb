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
  #
  # Changed: Detect inherited acceptances when overriding.
  # Why: When GP clicks "Set Own NDA" on a folder that had a signed inherited NDA,
  #   the form needs to show a resign checkbox. We resolve the effective NDA *before*
  #   the mode switches to "own" and count accepted investors scoped to this folder.
  #
  # @return [void] Renders the NDA settings modal with context-appropriate content.
  def new
    @nda_config = @owner.nda_config || @owner.build_nda_config
    authorize @nda_config

    @inheritance_state = if params[:override].present?
                           "own"
                         else
                           @folder.nda_inheritance_mode
                         end

    # Detect inherited acceptances when GP is overriding an inherited NDA.
    # Why: effective_nda_config walks the ancestry tree — must be called before
    #   the folder's mode changes to "own", otherwise it returns the new (empty) config.
    if params[:override].present? && @folder
      effective_nda = @folder.effective_nda_config
      if effective_nda&.enabled?
        folder_investor_ids = Investor.owner_access_rights(@folder, nil).pluck(:id)
        @inherited_accepted_count = effective_nda.nda_acceptances
                                                 .where(investor_id: folder_investor_ids, status: "accepted")
                                                 .select(:investor_id).distinct.count
      end
    end
    @inherited_accepted_count ||= 0
  end

  # POST /folders/:folder_id/nda_config
  # Changed: Captures the effective NDA before switching mode to "own" so acceptance
  #   migration can reference the inherited config's acceptances.
  # Why: Once mode switches to "own", effective_nda_config resolves to the new (empty)
  #   config — the inherited reference is lost. Capturing it first enables the resign
  #   choice: migrate acceptances (resign=false) or start fresh (resign=true).
  #
  # @return [void] Creates the NDA config and responds with turbo_stream to update modal and tree.
  def create
    # Capture the inherited NDA before mode switches to "own".
    # Why: effective_nda_config walks ancestry — after mode change it returns the new config.
    effective_nda_before_override = @folder&.effective_nda_config
    Rails.logger.info("[NDA_DEBUG] effective_nda_before_override=#{effective_nda_before_override&.id}, enabled=#{effective_nda_before_override&.enabled?}, folder_mode=#{@folder&.nda_inheritance_mode}")

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

        # Read the GP's resign choice from the override resign checkbox.
        # Why: When overriding an inherited NDA with existing acceptances, GP chooses
        #   whether to require re-sign (true = fresh start) or carry forward (false = migrate).
        resign_required = ActiveModel::Type::Boolean.new.cast(
          params.dig(:nda_config, :resign_required)
        )
        resign_required = false if resign_required.nil?

        create_version_record(@nda_config, resign_required: resign_required)

        # Migrate inherited acceptances when GP chose not to require re-sign.
        # Why: LPs who signed the inherited NDA should retain access to this folder
        #   without being blocked again. Copies acceptance records scoped to this folder's investors.
        Rails.logger.info("[NDA_DEBUG] resign_required=#{resign_required}, effective_nda_id=#{effective_nda_before_override&.id}, enabled=#{effective_nda_before_override&.enabled?}")
        if !resign_required && effective_nda_before_override&.enabled?
          Rails.logger.info("[NDA_DEBUG] Running migrate_inherited_acceptances")
          migrate_inherited_acceptances(effective_nda_before_override, @nda_config)
        else
          Rails.logger.info("[NDA_DEBUG] Skipping migration — resign=#{resign_required}, nda=#{effective_nda_before_override&.id}")
        end

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
          # Changed: Default to false when checkbox is unchecked (param not sent).
          # Why: Unchecked checkbox means GP does not want existing signatories to re-sign.
          resign_required = false if resign_required.nil?
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

  # Changed: Module 10 — folder-scoped auto-tag instead of entity-wide.
  # Why: The previous entity-wide query (InvestorAccess.where(entity_id:)) tagged signatories
  #   for ALL entity investors, including those without access to the specific folder. Now scoped
  #   via Investor.owner_access_rights to only tag investors with folder-level AccessRight records.
  #   Selecting the oldest approved InvestorAccess (by created_at) picks the user who has had
  #   access longest — a reasonable default. Rescue RecordNotUnique silently for idempotency.
  #
  # @param nda_config [NdaConfig] The newly created NDA config
  # @return [void]
  def auto_tag_default_signatories(nda_config)
    # Changed: Scope investors to folder-level access rights, not entity-wide.
    # Why: Only investors with an AccessRight on this folder should get NDA signatories.
    #   Uses the same Investor.owner_access_rights pattern as NdaStatusResolver#resolve_investors.
    folder_investor_ids = Investor.owner_access_rights(@folder, nil).pluck(:id)
    return if folder_investor_ids.empty?

    InvestorAccess
      .where(entity_id: nda_config.entity_id, investor_id: folder_investor_ids, approved: true)
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

  # Copies accepted NdaAcceptance records from the inherited NDA to the new child NDA.
  # Why: When GP overrides an inherited NDA and chooses not to require re-sign, LPs who
  #   already signed the inherited NDA should retain access. Copies are scoped to investors
  #   with folder-level AccessRight on this folder. Original records on the parent NDA are
  #   untouched — LP retains access to other folders inheriting from the parent.
  #
  # @param source_nda [NdaConfig] The inherited NDA config being overridden
  # @param target_nda [NdaConfig] The newly created NDA config on this folder
  # @return [void]
  def migrate_inherited_acceptances(source_nda, target_nda)
    folder_investor_ids = Investor.owner_access_rights(@folder, nil).pluck(:id)
    return if folder_investor_ids.empty?

    source_nda.nda_acceptances
              .where(investor_id: folder_investor_ids, status: "accepted")
              .find_each do |acceptance|
      NdaAcceptance.create!(
        nda_config: target_nda,
        investor_id: acceptance.investor_id,
        user_id: acceptance.user_id,
        entity_id: acceptance.entity_id,
        nda_version: 1,
        status: "accepted",
        accepted_at: acceptance.accepted_at
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
