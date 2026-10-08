# frozen_string_literal: true

# @description Controller for stakeholder-level LP NDA acceptance flow. Renders the NDA document
#   on a minimal layout and captures the LP's accept or decline decision as an NdaAcceptance record.
#   Resolves the current user's investor (stakeholder) via InvestorAccess so the acceptance
#   unlocks all users under that investor, not just the signing user.
#   Uses query params (nda_config_id, folder_id, return_to) instead of nested routes
#   because NdaConfig is polymorphic — not tied to any specific owner type.
#
# @see NdaAcceptance
# @see NdaAcceptancePolicy
# @see NdaConfig
# @see InvestorAccess — resolves which investor a user represents for a given entity
class NdaAcceptancesController < ApplicationController
  layout "modernize"

  # Changed: Added VALID_REASONS whitelist for Module 4 contextual re-acceptance notes.
  # Why: The gate passes a reason query param on redirect. Only whitelisted values are
  #   accepted — any other value is treated as nil (first-time acceptance, no note shown).
  # Changed: Added "revoked" to VALID_REASONS.
  # Why: Revoked LPs need a contextual note explaining their access was revoked by the GP.
  VALID_REASONS = %w[version_mismatch expired revoked].freeze

  # Changed: Skip CSRF verification for accept/decline actions.
  # Why: The Turbo Frame → Turbo.visit() redirect chain from DocumentsController#ensure_nda_accepted
  #   can cause CSRF token mismatch. These actions are safe to unprotect because they are already
  #   guarded by Devise authentication + Pundit policy (InvestorAccess check). The actions only
  #   create append-only audit records.
  skip_forgery_protection only: %i[create decline]

  # Changed: Skip policy scoping — this controller authorizes individual records, not collections.
  # Why: ApplicationController enforces verify_policy_scoped, but NDA acceptance actions
  #   operate on single NdaAcceptance instances via authorize(), not policy_scope().
  after_action :verify_authorized
  after_action :verify_policy_scoped, only: []

  before_action :set_nda_config
  before_action :set_folder
  # Changed: Module 9 — signatory guard prevents non-signatories from viewing or submitting
  #   the acceptance screen. Runs on index/create/decline but NOT on blocked/lapsed
  #   (blocked exclusion prevents infinite redirect loop; lapsed is a dead-end for all users).
  # Why: The folder gate redirects non-signatories to the blocked page, but a user could
  #   manually craft the acceptance URL. This guard is the server-side enforcement.
  before_action :ensure_signatory, only: %i[index create decline]
  before_action :resolve_investor, only: %i[create decline]

  # GET /nda_acceptances?nda_config_id=X&folder_id=Y&return_to=Z&reason=Y
  # Changed: Module 4 — reads optional reason param for contextual re-acceptance note.
  # Why: Gate redirects with reason=version_mismatch or reason=expired so the acceptance
  #   screen can show a note explaining why the LP must re-accept.
  # @return [void] Renders the NDA acceptance screen with PDF iframe and accept/decline buttons.
  def index
    @nda_acceptance = NdaAcceptance.new(nda_config: @nda_config)
    authorize @nda_acceptance, :show?
    @return_to = params[:return_to]
    @reason = VALID_REASONS.include?(params[:reason]) ? params[:reason] : nil
  end

  # POST /nda_acceptances?nda_config_id=X&folder_id=Y&return_to=Z
  # @return [void] Creates an NdaAcceptance with status=accepted on behalf of the user's
  #   investor (stakeholder) and redirects to return_to.
  def create
    @nda_acceptance = NdaAcceptance.new(
      nda_config: @nda_config,
      investor: @investor,
      user: current_user,
      entity: @nda_config.entity,
      status: "accepted",
      nda_version: @nda_config.version,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(500, omission: ""),
      accepted_at: Time.current
    )
    authorize @nda_acceptance

    if @nda_acceptance.save
      # Changed: Module 8 — fire accept notifications after successful save.
      # Why: GP team needs to know an LP accepted; other LP users of the same investor
      #   need to know they now have folder access. Notifications are background-only
      #   (deliver_later) — the redirect is never delayed.
      notify_acceptance(@nda_acceptance)
      redirect_to safe_return_to(params[:return_to])
    else
      flash.now[:alert] = "Unable to record your acceptance. Please try again."
      render :index, status: :unprocessable_entity
    end
  end

  # POST /nda_acceptances/decline?nda_config_id=X&folder_id=Y&return_to=Z
  # @return [void] Creates an NdaAcceptance with status=declined on behalf of the user's
  #   investor (stakeholder) and renders the decline page.
  def decline
    @nda_acceptance = NdaAcceptance.new(
      nda_config: @nda_config,
      investor: @investor,
      user: current_user,
      entity: @nda_config.entity,
      status: "declined",
      nda_version: @nda_config.version,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(500, omission: ""),
      declined_at: Time.current
    )
    authorize @nda_acceptance

    if @nda_acceptance.save
      # Changed: Module 8 — fire decline notification after successful save.
      # Why: GP team needs to know an LP declined. No LP notification on decline
      #   (avoids alarm — another signatory could still accept).
      notify_decline(@nda_acceptance)
      @return_to = params[:return_to]
      # Changed: Use 422 status so Turbo processes the response inside the turbo-frame.
      # Why: Turbo ignores 200 responses to POST requests (treats them as redirects it can't follow).
      #   A 422 tells Turbo to render the response body in the frame.
      render :declined, status: :unprocessable_entity
    else
      flash.now[:alert] = "Unable to record your response. Please try again."
      render :index, status: :unprocessable_entity
    end
  end

  # GET /nda_acceptances/lapsed?nda_config_id=X&folder_id=Y
  # Changed: Module 4 — dead-end page for specific-date NDAs whose validity_date has passed.
  # Why: Re-accepting a lapsed specific-date NDA would create an immediately-expired record
  #   (the config's date hasn't changed), causing an infinite loop. Instead, show a dead-end
  #   page directing the LP to contact the fund manager.
  # @return [void] Renders the lapsed NDA page with no accept/decline form.
  def lapsed
    @nda_acceptance = NdaAcceptance.new(nda_config: @nda_config)
    authorize @nda_acceptance, :show?
  end

  # GET /nda_acceptances/blocked?nda_config_id=X&folder_id=Y
  # Changed: Module 9 — dead-end page for non-signatory LP users.
  # Why: Only designated signatories can accept/decline the NDA. Non-signatories
  #   are redirected here from the folder gate (DocumentsController#ensure_nda_accepted)
  #   or from the ensure_signatory before_action. Shows a message explaining that a
  #   designated signatory must accept on their behalf. No PDF, no accept/decline buttons.
  # @return [void] Renders the blocked NDA page.
  def blocked
    @nda_acceptance = NdaAcceptance.new(nda_config: @nda_config)
    authorize @nda_acceptance, :show?
  end

  private

  # Changed: Module 9 — redirects non-signatories to the blocked page.
  # Why: Server-side enforcement that only designated signatories can view or submit
  #   the acceptance screen. Without this, a non-signatory could bypass the folder gate
  #   by manually navigating to /nda_acceptances?nda_config_id=X.
  #   Scoped to index/create/decline only — must NOT run on blocked (redirect loop)
  #   or lapsed (dead-end page shown to everyone).
  #
  # @return [void] Redirects to blocked page if current user is not a signatory.
  def ensure_signatory
    return if NdaSignatory.exists?(nda_config_id: @nda_config.id, user_id: current_user.id)

    redirect_to blocked_nda_acceptances_path(nda_config_id: @nda_config.id, folder_id: params[:folder_id])
  end

  # @return [void] Loads the NdaConfig from params. Raises RecordNotFound if missing/invalid.
  def set_nda_config
    @nda_config = NdaConfig.find(params[:nda_config_id])
  end

  # @return [void] Loads the Folder from params for display context. Optional — may be nil
  #   for future non-folder NDA owners.
  def set_folder
    @folder = Folder.find_by(id: params[:folder_id])
  end

  # @return [void] Resolves the investor (stakeholder) that the current user represents
  #   for the NDA config's entity. Raises RecordNotFound if the user has no approved
  #   InvestorAccess for this entity.
  def resolve_investor
    investor_access = InvestorAccess.where(
      user_id: current_user.id,
      entity_id: @nda_config.entity_id,
      approved: true
    ).first!
    @investor = investor_access.investor
  end

  # Changed: Module 8 — sends GP accept notification + LP acceptance confirmation.
  # Why: GP notification_emails receive "NDA Accepted" via direct mailer delivery.
  #   Other LP users of the investor receive "NDA Access Granted" via NdaEventNotifier.
  #   The signer is excluded from LP confirmation (they already know).
  #
  # @param acceptance [NdaAcceptance] the just-saved acceptance record
  # @return [void]
  def notify_acceptance(acceptance)
    folder_name = @folder&.name || acceptance.nda_config.owner&.name
    recipients = NdaNotificationRecipients.resolve(:accepted, acceptance.nda_config, acceptance.investor)

    gp_params = {
      entity_id: acceptance.entity_id,
      investor_name: acceptance.investor.name,
      folder_name: folder_name,
      nda_version: acceptance.nda_version,
      signed_by: acceptance.user.full_name,
      signed_at: acceptance.accepted_at
    }

    # Changed: Send directly to each GP notification email (not through Noticed).
    # Why: notification_emails are external addresses, not system Users.
    recipients[:gp_emails].each do |email|
      NdaMailer.with(gp_params.merge(direct_to: email)).nda_accepted.deliver_later
    end

    # Changed: Send LP acceptance confirmation via Noticed (includes signer).
    # Why: The signer should also receive a confirmation email that their NDA
    #   acceptance was recorded and folder access is now open. Previously the
    #   signer was excluded via exclude_user_id — removed so all LP users of
    #   the investor (including the signer) get the "NDA Access Granted" email.
    confirm_recipients = NdaNotificationRecipients.resolve(
      :acceptance_confirm, acceptance.nda_config, acceptance.investor
    )
    confirm_recipients[:lp_users].each do |user|
      NdaEventNotifier.with(
        entity_id: acceptance.entity_id,
        email_method: :nda_acceptance_confirm,
        record: acceptance,
        folder_name: folder_name,
        signed_by: acceptance.user.full_name,
        signed_at: acceptance.accepted_at,
        folder_link: folder_link_for(acceptance.nda_config)
      ).deliver_later(user)
    end
  rescue StandardError => e
    # Changed: Rescue notification errors to never block the acceptance flow.
    # Why: The acceptance is already saved — notification failure is non-critical.
    Rails.logger.error("[NdaNotification] Accept notification failed: #{e.message} (acceptance_id=#{acceptance.id})")
  end

  # Changed: Module 8 — sends GP decline notification.
  # Why: GP notification_emails receive "NDA Declined" via direct mailer delivery.
  #   No LP notification on decline (another signatory could still accept).
  #
  # @param acceptance [NdaAcceptance] the just-saved decline record
  # @return [void]
  def notify_decline(acceptance)
    recipients = NdaNotificationRecipients.resolve(:declined, acceptance.nda_config, acceptance.investor)
    folder_name = @folder&.name || acceptance.nda_config.owner&.name

    gp_params = {
      entity_id: acceptance.entity_id,
      investor_name: acceptance.investor.name,
      folder_name: folder_name,
      nda_version: acceptance.nda_version,
      declined_by: acceptance.user.full_name,
      declined_at: acceptance.declined_at,
      direct_to: nil
    }

    recipients[:gp_emails].each do |email|
      NdaMailer.with(gp_params.merge(direct_to: email)).nda_declined.deliver_later
    end
  rescue StandardError => e
    Rails.logger.error("[NdaNotification] Decline notification failed: #{e.message} (acceptance_id=#{acceptance.id})")
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

  # Changed: Added folder_link_for helper for absolute URLs in email links.
  # Why: Email clients need full URLs with host — relative paths don't resolve.
  #
  # @param nda_config [NdaConfig] the NDA config
  # @return [String, nil] the absolute folder URL for email links
  def folder_link_for(nda_config)
    return nil unless nda_config.owner.is_a?(Folder)

    folder_documents_url(entity_id: nda_config.entity_id, folder_id: nda_config.owner_id)
  end
end
