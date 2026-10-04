# frozen_string_literal: true

# @description Controller for LP NDA acceptance flow. Renders the NDA document on a
#   minimal layout and captures the LP's accept or decline decision as an NdaAcceptance record.
#   Uses query params (nda_config_id, folder_id, return_to) instead of nested routes
#   because NdaConfig is polymorphic — not tied to any specific owner type.
#
# @see NdaAcceptance
# @see NdaAcceptancePolicy
# @see NdaConfig
class NdaAcceptancesController < ApplicationController
  layout "nda_minimal"

  # Changed: Skip policy scoping — this controller authorizes individual records, not collections.
  # Why: ApplicationController enforces verify_policy_scoped, but NDA acceptance actions
  #   operate on single NdaAcceptance instances via authorize(), not policy_scope().
  after_action :verify_authorized
  after_action :verify_policy_scoped, only: []

  before_action :set_nda_config
  before_action :set_folder

  # GET /nda_acceptances?nda_config_id=X&folder_id=Y&return_to=Z
  # @return [void] Renders the NDA acceptance screen with PDF iframe and accept/decline buttons.
  def index
    @nda_acceptance = NdaAcceptance.new(nda_config: @nda_config)
    authorize @nda_acceptance, :show?
    @return_to = params[:return_to]
  end

  # POST /nda_acceptances?nda_config_id=X&folder_id=Y&return_to=Z
  # @return [void] Creates an NdaAcceptance with status=accepted and redirects to return_to.
  def create
    @nda_acceptance = NdaAcceptance.new(
      nda_config: @nda_config,
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
  # @return [void] Creates an NdaAcceptance with status=declined and renders the decline page.
  def decline
    @nda_acceptance = NdaAcceptance.new(
      nda_config: @nda_config,
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
      render :declined
    else
      flash.now[:alert] = "Unable to record your response. Please try again."
      render :index, status: :unprocessable_entity
    end
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
