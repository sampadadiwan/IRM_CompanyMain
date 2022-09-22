class PermissionsController < ApplicationController
  # prepend_view_path 'app/packs/core/permissions/views'
  before_action :set_permission, only: %i[show edit update destroy]

  # GET /permissions or /permissions.json
  def index
    @permissions = policy_scope(Permission).includes(:user, :owner, :granted_by, :entity)
  end

  # GET /permissions/1 or /permissions/1.json
  def show; end

  # GET /permissions/new
  def new
    @permission = Permission.new(permission_params)
    @permission.entity_id = current_user.entity_id
    authorize(@permission)
  end

  # GET /permissions/1/edit
  def edit; end

  # POST /permissions or /permissions.json
  def create
    @permission = Permission.new(permission_params)
    @permission.entity_id = current_user.entity_id
    @permission.granted_by_id = current_user.id

    authorize(@permission)
    respond_to do |format|
      if @permission.save
        format.html { redirect_to permission_url(@permission), notice: "Permission was successfully created." }
        format.json { render :show, status: :created, location: @permission }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @permission.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /permissions/1 or /permissions/1.json
  def update
    @permission.entity_id = current_user.entity_id
    @permission.entity_id = current_user.entity_id
    @permission.granted_by_id = current_user.id

    respond_to do |format|
      if @permission.update(permission_params)
        format.html { redirect_to permission_url(@permission), notice: "Permission was successfully updated." }
        format.json { render :show, status: :ok, location: @permission }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @permission.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /permissions/1 or /permissions/1.json
  def destroy
    @permission.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@permission)
        ]
      end
      format.html { redirect_to permissions_url, notice: "Permission was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_permission
    @permission = Permission.find(params[:id])
    authorize(@permission)
  end

  # Only allow a list of trusted parameters through.
  def permission_params
    params.require(:permission).permit(:user_id, :owner_id, :owner_type, :email, :role,
                                       :entity_id, :granted_by_id, permissions: [])
  end
end
