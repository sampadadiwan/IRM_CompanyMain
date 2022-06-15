class DocumentsController < ApplicationController
  before_action :set_document, only: %w[show update destroy edit]
  after_action :verify_authorized, except: %i[index search investor_documents]
  after_action :verify_policy_scoped, only: []

  before_action do
    ActiveStorage::Current.host = request.base_url
  end

  impressionist actions: [:show]

  # GET /documents or /documents.json
  def index
    if params[:entity_id].present?
      @entity = Entity.find(params[:entity_id])
      @documents = Document.for_investor(current_user, @entity)
      @folders, _map = Folder.build_full_tree(Folder.joins(:documents).merge(@documents).order(parent_folder_id: :asc).distinct)
      @show_steps = false
    else
      @entity = current_user.entity
      @documents = policy_scope(Document)
      @folders, _map = Folder.build_full_tree(Folder.where(entity_id: @entity.id).order(parent_folder_id: :asc))
      @show_steps = true
    end

    @documents = @documents.order(id: :desc)
    @documents = @documents.where(folder_id: params[:folder_id]) if params[:folder_id].present?
    @documents = @documents.joins(:folder).includes(:folder, :tags).page params[:page]
  end

  def investor_documents
    if params[:entity_id].present?
      @entity = Entity.find(params[:entity_id])
      @documents = Document.for_investor(current_user, @entity)
    end

    @folders, _map = Folder.build_full_tree(Folder.joins(:documents).merge(@documents).distinct)
    @documents = @documents.order(id: :desc).page params[:page]

    render "index"
  end

  def search
    @entity = params[:entity_id].present? ? Entity.find(params[:entity_id]) : current_user.entity
    query = params[:query]
    if query.present?
      @documents = DocumentIndex.filter(term: { entity_id: @entity.id })
                                .query(query_string: { fields: DocumentIndex::SEARCH_FIELDS,
                                                       query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to documents_path
    end
  end

  # GET /documents/1 or /documents/1.json
  def show; end

  # GET /documents/new
  def new
    @document = Document.new(document_params)
    # Custom form fields
    form_type = FormType.where(entity_id: current_user.entity_id, name: "Document").first
    @document.form_type = form_type

    authorize @document
  end

  # GET /documents/1/edit
  def edit; end

  # POST /documents or /documents.json
  def create
    @document = Document.new(document_params)
    @document.entity_id = current_user.entity_id
    authorize @document

    respond_to do |format|
      if @document.save
        format.html { redirect_to document_url(@document), notice: "Document was successfully created." }
        format.json { render :show, status: :created, location: @document }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @document.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /documents/1 or /documents/1.json
  def update
    respond_to do |format|
      if @document.update(document_params)
        format.html { redirect_to document_url(@document), notice: "Document was successfully updated." }
        format.json { render :show, status: :ok, location: @document }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @document.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /documents/1 or /documents/1.json
  def destroy
    @document.destroy

    respond_to do |format|
      format.html { redirect_to documents_url, notice: "Document was successfully deleted." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_document
    @document = Document.find(params[:id])
    authorize @document
  end

  # Only allow a list of trusted parameters through.
  def document_params
    params.require(:document).permit(:name, :file, :text, :entity_id, :video, :form_type_id,
                                     :tag_list, :folder_id, properties: {})
  end
end
