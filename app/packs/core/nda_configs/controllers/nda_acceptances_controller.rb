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
  VALID_REASONS = %w[version_mismatch expired].freeze

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

  private

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
end
