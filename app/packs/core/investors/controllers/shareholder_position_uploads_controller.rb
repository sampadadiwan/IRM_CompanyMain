class ShareholderPositionUploadsController < ApplicationController
  # A ShareholderPosition bulk xlsx upload has its own dedicated new/create/validate_upload
  # stack - mirroring how KPI reports have their own dedicated upload+validate flow
  # (KpiReportsController#validate_upload / kpi_xlsx_report_controller.js) - so the Fully
  # Dilluted % pre-Save check (ValidateShareholderPositionPercentages,
  # shareholder_position_percentage_check_controller.js) never has to touch the generic
  # ImportUploadsController or its shared new/edit/_xlsx_preview views used by every other bulk
  # import type. Still persists via the same ImportUpload model (import_type:
  # "ShareholderPosition") - the real import pipeline (ImportShareholderPosition) is unchanged.

  # GET /shareholder_position_uploads/new
  def new
    @import_upload = ImportUpload.new(import_type: "ShareholderPosition", owner_id: params[:owner_id], owner_type: params[:owner_type])
    @import_upload.user_id = current_user.id
    if @import_upload.owner
      @import_upload.entity_id = @import_upload.owner_type == "Entity" ? @import_upload.owner.id : @import_upload.owner.entity_id
    else
      @import_upload.owner = current_user.entity
      @import_upload.entity_id = current_user.entity_id
    end

    authorize @import_upload, policy_class: ImportUploadPolicy
  end

  # POST /shareholder_position_uploads
  def create
    @import_upload = ImportUpload.new(import_upload_params)
    @import_upload.import_type = "ShareholderPosition"
    @import_upload.user_id = current_user.id
    authorize @import_upload, policy_class: ImportUploadPolicy

    if @import_upload.save
      notice = @import_upload.status.blank? ? "Import in progress" : "Import Status: #{@import_upload.status}"
      redirect_to import_upload_url(@import_upload), notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  # POST /shareholder_position_uploads/validate_upload
  #
  # Dry-run check (writes nothing, saves no ImportUpload) run the moment a file is chosen on the
  # New page, so a problem can be fixed and re-uploaded before Save is ever clicked - see
  # shareholder_position_percentage_check_controller.js.
  def validate_upload
    import_upload = ImportUpload.new(import_type: "ShareholderPosition", owner: current_user.entity, entity_id: current_user.entity_id)
    authorize import_upload, :create?, policy_class: ImportUploadPolicy

    result = ValidateShareholderPositionPercentages.call(file_data: params[:file_data], file: params[:file])
    render json: { ok: result[:errors].blank?, errors: result[:errors] || [] }
  end

  private

  def import_upload_params
    params.require(:import_upload).permit(:name, :entity_id, :owner_id, :owner_type, :import_file)
  end
end
