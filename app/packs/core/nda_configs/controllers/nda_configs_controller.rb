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
  # @return [void] Renders the NDA settings modal with an empty or existing config form.
  def new
    @nda_config = @owner.nda_config || @owner.build_nda_config
    authorize @nda_config
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
        flash.now[:notice] = "NDA settings saved successfully."
        format.turbo_stream
        format.html { redirect_to @owner, notice: "NDA settings saved successfully." }
      else
        format.turbo_stream { render :form_update, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  # GET /folders/:folder_id/nda_config/edit
  # @return [void] Renders the NDA settings modal with pre-filled config values.
  def edit
    authorize @nda_config
  end

  # PATCH /folders/:folder_id/nda_config
  # @return [void] Updates the NDA config and responds with turbo_stream to update modal and tree.
  def update
    authorize @nda_config
    @nda_config.updated_by = current_user

    respond_to do |format|
      if @nda_config.update(nda_config_params)
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

    return if @owner.entity_id == current_user.entity_id

    raise Pundit::NotAuthorizedError, "not allowed to access this resource"
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
