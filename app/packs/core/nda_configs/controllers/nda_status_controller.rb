# frozen_string_literal: true

# GP-facing NDA status dashboard controller.
# Provides a modal summary tab (Turbo Frame), a dedicated AG Grid dashboard page
# with XLSX export, user-level exemption management, and signatory tagging.
#
# All actions are restricted to GP employees of the same entity via NdaStatusPolicy.
#
# @see NdaStatusPolicy
# @see NdaStatusResolver
# @see NdaExemption
# @see NdaSignatory
class NdaStatusController < ApplicationController
  before_action :set_nda_config
  before_action :set_folder, only: %i[summary index]

  # Changed: Skip policy_scope verification for the index action.
  # Why: Dashboard data comes from NdaStatusResolver (a service), not a model scope.
  #   Authorization is handled at the record level via `authorize @nda_config`.
  skip_after_action :verify_policy_scoped, only: [:index]

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

  # POST /nda_status/exemptions?nda_config_id=X&user_id=Y&reason=Z
  # Creates a user-level NDA exemption. Returns JSON for AG Grid row update.
  # exempted_by_id is set server-side from current_user, never from params.
  #
  # @return [void]
  def create_exemption
    authorize @nda_config, policy_class: NdaStatusPolicy

    # Changed: exempted_by_id set server-side, not from params.
    # Why: Security — GP identity must come from session, not user input.
    exemption = NdaExemption.create!(
      nda_config_id: @nda_config.id,
      user_id: params[:user_id],
      exempted_by_id: current_user.id,
      reason: params[:reason]
    )

    render json: { status: "ok", user_id: exemption.user_id, exempt: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: "User already exempt from this NDA" }, status: :conflict
  end

  # DELETE /nda_status/exemptions/:id
  # Revokes a user-level NDA exemption. Returns JSON for AG Grid row update.
  #
  # @return [void]
  def destroy_exemption
    authorize @nda_config, policy_class: NdaStatusPolicy

    exemption = NdaExemption.find(params[:id])
    user_id = exemption.user_id
    exemption.destroy!

    render json: { status: "ok", user_id: user_id, exempt: false }
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

  # @return [void] Loads the NDA config from params.
  def set_nda_config
    @nda_config = NdaConfig.find(params[:nda_config_id])
  end

  # @return [void] Loads the folder from params.
  def set_folder
    @folder = Folder.find(params[:folder_id])
  end
end
