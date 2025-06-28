class ImportUploadsController < ApplicationController
  before_action :set_import_upload, only: %i[show edit update destroy delete_data]

  # GET /import_uploads or /import_uploads.json
  def index
    authorize(ImportUpload)
    @q = ImportUpload.ransack(params[:q])
    @import_uploads = policy_scope(@q.result).includes(:user, :owner).order(id: :desc)
    @pagy, @import_uploads = pagy(@import_uploads)
  end

  # GET /import_uploads/1 or /import_uploads/1.json
  def show; end

  # GET /import_uploads/new
  def new
    @import_upload = ImportUpload.new(import_upload_params)
    @import_upload.user_id = current_user.id
    # For Advisors we need to allow them to import data, so we do this
    # The advisors will have ability to create on the owner - see policy
    if @import_upload.owner
      @import_upload.entity_id = if @import_upload.owner_type == "Entity"
                                   @import_upload.owner.id
                                 else
                                   @import_upload.owner.entity_id
                                 end

    else
      @import_upload.owner = current_user.entity
      @import_upload.entity_id = current_user.entity_id
    end

    authorize @import_upload
  end

  # GET /import_uploads/1/edit
  def edit; end

  # POST /import_uploads or /import_uploads.json
  def create
    @import_upload = ImportUpload.new(import_upload_params)
    @import_upload.user_id = current_user.id
    authorize @import_upload

    respond_to do |format|
      if @import_upload.save
        notice = @import_upload.status.blank? ? "Import in progress" : "Import Status: #{@import_upload.status}"
        format.html { redirect_to import_upload_url(@import_upload), notice: }
        format.json { render :show, status: :created, location: @import_upload }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @import_upload.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /import_uploads/1 or /import_uploads/1.json
  def update
    respond_to do |format|
      if @import_upload.update(import_upload_params)
        format.html { redirect_to import_upload_url(@import_upload), notice: "Import upload was successfully updated." }
        format.json { render :show, status: :ok, location: @import_upload }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @import_upload.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /import_uploads/1 or /import_uploads/1.json
  def destroy
    @import_upload.destroy

    respond_to do |format|
      format.html { redirect_to import_uploads_url, notice: "Import upload was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def delete_data
    ImportUploadDeleteAllJob.perform_later(@import_upload.id, current_user.id)
    redirect_to import_upload_path(@import_upload), notice: "Imported data deletion started. It will take a few mins."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_import_upload
    @import_upload = ImportUpload.find(params[:id])
    @bread_crumbs = { Uploads: import_uploads_path, "#{@import_upload.name}": import_upload_path(@import_upload) }
    authorize @import_upload
  end

  # Only allow a list of trusted parameters through.
  def import_upload_params
    params.require(:import_upload).permit(:name, :entity_id, :owner_id, :owner_type,
                                          :user_references, :import_type, :import_file,
                                          :status, :error_text)
  end
end
