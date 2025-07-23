class FoldersController < ApplicationController
  before_action :set_folder, only: %i[show edit update destroy download generate_report]
  after_action :verify_authorized, except: %i[index data_rooms]

  # GET /folders or /folders.json
  def index
    @folders = policy_scope(Folder).order("full_path").includes(:parent)
    @folders = @folders.not_system if params[:all].blank?
  end

  # Returns a list of data_rooms for the current user
  def data_rooms; end

  # GET /folders/1 or /folders/1.json
  def show; end

  # GET /folders/new
  def new
    @folder = Folder.new(folder_params)
    authorize @folder
  end

  def download
    DocumentDownloadJob.perform_later(@folder.id, current_user.id)
    UserAlert.new(
      user: current_user,
      message: "You will be sent a download link for the documents in a few minutes.",
      level: "info"
    ).broadcast
    head :ok
  end

  def generate_report
    if request.post?
      report_template_name = params[:report_template_name]
      if report_template_name.present?
        FolderLlmReportJob.perform_later(@folder.id, current_user.id, report_template_name:)
        redirect_to @folder.owner, notice: "Report generation has been started. You will be notified when it is ready."
      else
        redirect_to request.referer, alert: "Report Template is required"
      end
    else
      render "generate_report"
    end
  end

  # GET /folders/1/edit
  def edit; end

  # POST /folders or /folders.json
  def create
    @folder = Folder.new(folder_params)
    @folder.entity_id = @folder.parent.entity_id
    authorize @folder

    setup_doc_user(@folder)

    respond_to do |format|
      if @folder.save
        format.html { redirect_to folder_url(@folder), notice: "Folder was successfully created." }
        format.json { render :show, status: :created, location: @folder }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @folder.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /folders/1 or /folders/1.json
  def update
    setup_doc_user(@folder)

    respond_to do |format|
      if @folder.update(folder_params)
        format.html { redirect_to folder_url(@folder), notice: "Folder was successfully updated." }
        format.json { render :show, status: :ok, location: @folder }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @folder.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /folders/1 or /folders/1.json
  def destroy
    @folder.destroy

    respond_to do |format|
      format.html { redirect_to folders_url, notice: "Folder was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_folder
    @folder = Folder.find(params[:id])
    authorize @folder
  end

  # Only allow a list of trusted parameters through.
  def folder_params
    params.require(:folder).permit(:name, :knowledge_base, :parent_id, :full_path, :level, :entity_id, :download, :printing, :orignal, docs: [], documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
