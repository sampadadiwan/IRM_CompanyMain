# frozen_string_literal: true

# GP-facing NDA status dashboard controller.
# Provides a modal summary tab (Turbo Frame), a dedicated dashboard page
# with XLSX export, and signatory tagging.
#
# Changed: Removed exemption actions — exemption is now a boolean on InvestorAccess.
# Why: Per product decision (2026-10-05) — exemption is stakeholder-level, managed
#   from InvestorAccess form, not from the NDA dashboard.
#
# All actions are restricted to GP employees of the same entity via NdaStatusPolicy.
#
# @see NdaStatusPolicy
# @see NdaStatusResolver
# @see NdaSignatory
class NdaStatusController < ApplicationController
  before_action :set_nda_config
  before_action :set_folder, only: %i[summary index]

  # Changed: Skip policy_scope verification for actions that use service-level auth.
  # Why: Dashboard data comes from NdaStatusResolver (a service), not a model scope.
  #   Authorization is handled at the record level via `authorize @nda_config`.
  skip_after_action :verify_policy_scoped, only: %i[index revoke send_reminders]

  # GET /nda_status/summary?nda_config_id=X&folder_id=Y
  # Renders the Status tab content inside the NDA Settings modal via Turbo Frame.
  #
  # @return [void]
  def summary
    authorize @nda_config, policy_class: NdaStatusPolicy
    @status_data = NdaStatusResolver.resolve(@nda_config, @folder)
    render partial: "nda_status/summary", locals: { status_data: @status_data, nda_config: @nda_config, folder: @folder }
  end

  # GET /nda_status?nda_config_id=X&folder_id=Y
  # Renders the dedicated dashboard page (HTML), AG Grid data (JSON), or XLSX export.
  #
  # @return [void]
  def index
    authorize @nda_config, policy_class: NdaStatusPolicy
    @status_data = NdaStatusResolver.resolve(@nda_config, @folder)

    # Changed: Load version history records for the dashboard collapsible section.
    # Why: GP needs to see all NDA versions with upload date, uploader, resign decision,
    #   and a download link for each version's PDF. Eager-load uploaded_by to avoid N+1.
    @version_records = @nda_config.nda_config_versions
                                  .includes(:uploaded_by)
                                  .order(version: :desc)

    # Changed: Set breadcrumbs for the standard layout breadcrumb partial.
    # Why: Matches the app-wide breadcrumb style (Home • Documents • Folder — NDA Status).
    @bread_crumbs = [
      ["Documents", folder_documents_path(entity_id: @folder.entity_id, folder_id: @folder.id)],
      ["#{@folder.name} — NDA Status", nil]
    ]

    respond_to do |format|
      format.html { render layout: "modernize" }
      format.json { render "index" }
      format.xlsx
    end
  end

  # POST /nda_status/signatories?nda_config_id=X&user_id=Y
  # Tags a user as a designated NDA signatory for this NDA config.
  # tagged_by_id is set server-side from current_user, never from params.
  #
  # Changed: Added signatory tagging action.
  # Why: Replaces entity-wide InvestorAccess tag_list with per-NDA signatory designation.
  #
  # @return [void]
  def create_signatory
    authorize @nda_config, policy_class: NdaStatusPolicy

    signatory = NdaSignatory.create!(
      nda_config_id: @nda_config.id,
      user_id: params[:user_id],
      tagged_by_id: current_user.id
    )

    render json: { status: "ok", user_id: signatory.user_id, nda_tagged: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: "User is already a signatory for this NDA" }, status: :conflict
  end

  # POST /nda_status/revoke?nda_config_id=X&investor_id=Y&reason=Z
  # Changed: Module 8 — GP revokes an accepted investor's NDA.
  # Why: Creates a new NdaAcceptance with status=revoked (append-only audit trail).
  #   Fires revocation notification to LP users of the investor. investor_id from
  #   params is validated against the NdaConfig's entity. user_id is always current_user.
  #
  # @return [void]
  def revoke
    authorize @nda_config, policy_class: NdaStatusPolicy

    investor = Investor.find(params[:investor_id])

    # Changed: Validate investor has InvestorAccess for this entity.
    # Why: Prevents revoking an investor from another entity via crafted params.
    unless InvestorAccess.exists?(entity_id: @nda_config.entity_id, investor_id: investor.id, approved: true)
      render json: { error: "Investor not found for this entity" }, status: :not_found
      return
    end

    # Changed: Validate investor has an accepted NDA to revoke.
    # Why: Only "Accepted" investors can be revoked. Pending/Declined/Revoked cannot.
    latest_acceptance = NdaAcceptance
                        .where(nda_config_id: @nda_config.id, investor_id: investor.id)
                        .order(created_at: :desc)
                        .first

    unless latest_acceptance&.accepted?
      render json: { error: "Investor does not have an accepted NDA to revoke" }, status: :unprocessable_entity
      return
    end

    revocation = NdaAcceptance.new(
      nda_config: @nda_config,
      investor: investor,
      user: current_user,
      entity_id: @nda_config.entity_id,
      status: "revoked",
      reason: params[:reason].presence,
      nda_version: latest_acceptance.nda_version,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(500, omission: "")
    )

    if revocation.save
      # Changed: Fire revocation notification to LP users.
      # Why: All InvestorAccess users of the revoked investor should know they lost access.
      notify_revocation(revocation, investor)
      render json: { status: "ok", investor_id: investor.id, new_status: "Revoked" }
    else
      render json: { error: revocation.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # POST /nda_status/send_reminders?nda_config_id=X
  # Changed: Module 8 — GP sends bulk NDA reminders to pending investors' signatories.
  # Why: Enqueues NdaReminderJob in background. Returns count of users who will be emailed.
  #   If no pending investors exist, returns 422.
  #
  # @return [void]
  def send_reminders
    authorize @nda_config, policy_class: NdaStatusPolicy

    # Changed: Preview recipient count before enqueuing the job.
    # Why: Flash message needs to tell the GP how many users will be reminded.
    recipients = NdaNotificationRecipients.resolve(:reminder, @nda_config)
    user_count = recipients[:lp_users].size

    if user_count.zero?
      render json: { error: "No pending investors to remind" }, status: :unprocessable_entity
      return
    end

    NdaReminderJob.perform_later(@nda_config.id)
    render json: { status: "ok", users_notified: user_count, message: "Reminders sent to #{user_count} users" }
  end

  # DELETE /nda_status/signatories/:id
  # Removes a user's signatory designation for this NDA config.
  #
  # Changed: Added signatory untagging action.
  # Why: Replaces entity-wide InvestorAccess tag_list with per-NDA signatory designation.
  #
  # @return [void]
  def destroy_signatory
    authorize @nda_config, policy_class: NdaStatusPolicy

    signatory = NdaSignatory.find(params[:id])
    user_id = signatory.user_id
    signatory.destroy!

    render json: { status: "ok", user_id: user_id, nda_tagged: false }
  end

  private

  # Changed: Module 8 — sends revocation notification to LP users.
  # Why: All InvestorAccess users of the revoked investor need to know their
  #   folder access was revoked and they must re-accept.
  #
  # @param revocation [NdaAcceptance] the just-saved revocation record
  # @param investor [Investor] the revoked investor
  # @return [void]
  def notify_revocation(revocation, investor)
    recipients = NdaNotificationRecipients.resolve(:revoked, @nda_config, investor)
    folder_name = @nda_config.owner&.name

    recipients[:lp_users].each do |user|
      NdaEventNotifier.with(
        entity_id: @nda_config.entity_id,
        email_method: :nda_revoked,
        record: revocation,
        folder_name: folder_name,
        contact_email: @nda_config.contact_email,
        reason: revocation.reason
      ).deliver_later(user)
    end
  rescue StandardError => e
    Rails.logger.error("[NdaNotification] Revocation notification failed: #{e.message} (acceptance_id=#{revocation.id})")
  end

  # @return [void] Loads the NDA config from params.
  def set_nda_config
    @nda_config = NdaConfig.find(params[:nda_config_id])
  end

  # @return [void] Loads the folder from params.
  def set_folder
    @folder = Folder.find(params[:folder_id])
  end
end
