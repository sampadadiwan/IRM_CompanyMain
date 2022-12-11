class ImportUploadsController < ApplicationController
  before_action :set_import_upload, only: %i[show edit update destroy]

  # GET /import_uploads or /import_uploads.json
  def index
    @import_uploads = policy_scope(ImportUpload)
  end

  # GET /import_uploads/1 or /import_uploads/1.json
  def show; end

  # GET /import_uploads/new
  def new
    @import_upload = ImportUpload.new(import_upload_params)
    @import_upload.user_id = current_user.id
    authorize @import_upload
  end

  # GET /import_uploads/1/edit
  def edit; end

  # POST /import_uploads or /import_uploads.json
  def create
    @import_upload = ImportUpload.new(import_upload_params)
    @import_upload.user_id = current_user.id
    @import_upload.entity_id = @import_upload.owner.entity_id if @import_upload.owner

    authorize @import_upload

    respond_to do |format|
      if @import_upload.save
        format.html { redirect_to import_upload_url(@import_upload), notice: "Import upload was successfully created." }
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

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_import_upload
    @import_upload = ImportUpload.find(params[:id])
    authorize @import_upload
  end

  # Only allow a list of trusted parameters through.
  def import_upload_params
    params.require(:import_upload).permit(:name, :entity_id, :owner_id, :owner_type,
                                          :user_references, :import_type, :import_file,
                                          :status, :error_text)
  end
end
