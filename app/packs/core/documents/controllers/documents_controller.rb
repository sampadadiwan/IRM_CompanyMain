class DocumentsController < ApplicationController
  # prepend_view_path 'app/packs/core/documents/views'

  include ActiveStorage::SetCurrent

  before_action :set_document, only: %w[show update destroy edit sign]
  after_action :verify_authorized, except: %i[index search investor_documents]
  after_action :verify_policy_scoped, only: []
  # skip_before_action :authenticate_user!, :only => [:show]

  impressionist actions: [:show]

  # GET /documents or /documents.json
  def index
    if params[:owner_id].present? && params[:owner_type].present?
      # This is typicaly for investors to view documents of a sale, offer, commitment etc
      owner_documents
    elsif params[:entity_id].present?
      # This is typicaly for investors to view another entity's documents
      entity_documents
    else
      # See your own docs
      @entity = current_user.entity
      @documents = policy_scope(Document)
      authorize(Document)
      @show_steps = true
    end

    @documents = @documents.where(owner_tag: params[:owner_tag]) if params[:owner_tag].present?

    # Display docs of the folder and its children, like for data room
    if params[:folder_id].present?
      @folder = Folder.find(params[:folder_id])

      # Ensure that the IA user has access to the folder, as IAs can only access certain funds/deals etc
      authorize(@folder.owner, :show?) if @folder.owner # && current_user.investor_advisor?

      @documents = @documents.joins(:folder).merge(Folder.descendants_of(params[:folder_id]))
      @documents = @documents.or(Document.where(folder_id: params[:folder_id]))
    elsif current_user.investor_advisor?
      raise Pundit::NotAuthorizedError, "Advisors can access documents only in specific folders"
    else
      # This is specifically for investor advisors, who should not be able to see the docs for other funds
      @documents = @documents.where(owner_type: nil)  unless current_user.has_cached_role?(:company_admin) # if params[:hide_fund_docs] == "true"
    end

    # Newest docs first
    @documents = @documents.includes(:folder).order(id: :desc)
    @documents = @documents.page(params[:page]) if params[:all].blank?
  end

  def investor_documents
    if params[:entity_id].present?
      @entity = Entity.find(params[:entity_id])
      @documents = Document.for_investor(current_user, @entity)
    end

    @documents = @documents.order(id: :desc).page params[:page]

    @no_folders = false
    render "index"
  end

  def search
    @entity = params[:entity_id].present? ? Entity.find(params[:entity_id]) : current_user.entity
    query = params[:query]
    if query.present?
      @documents = DocumentIndex.filter(term: { entity_id: @entity.id })
                                .query(query_string: { fields: DocumentIndex::SEARCH_FIELDS,
                                                       query:, default_operator: 'and' })

      @documents = @documents.page(params[:page]).objects
      # @no_folders = true
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
    @document.setup_folder_defaults
    setup_custom_fields(@document)
    authorize @document
  end

  # GET /documents/1/edit
  def edit
    setup_custom_fields(@document)
  end

  # POST /documents or /documents.json
  def create
    @document = Document.new(document_params)
    @document.entity_id = @document.owner&.entity_id || current_user.entity_id
    @document.user_id = current_user.id
    authorize @document

    respond_to do |format|
      if @document.save
        format.html do
          if @document.owner
            redirect_to [@document.owner, { tab: "docs-tab" }], notice: "Document was successfully created."
          else
            redirect_to document_url(@document), notice: "Document was successfully created."
          end
        end
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
      format.html do
        if @document.owner
          redirect_to [@document.owner, { tab: "documents-tab" }], notice: "Document was successfully deleted."
        else
          redirect_to documents_url, notice: "Document was successfully deleted."
        end
      end
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_document
    @document = Document.find(params[:id])
    authorize @document
  end

  def entity_documents
    # We are trying to get documents that belong to some entity
    @entity = Entity.find(params[:entity_id])
    # Show all the documents for the investor for that entity
    @documents = if current_user.entity_id == @entity.id
                   @entity.documents
                 else
                   Document.for_investor(current_user, @entity)
                 end
    @show_steps = false
  end

  def owner_documents
    # We are trying to get documents that belong to some entity
    @owner = nil
    if params[:owner_type].present? && params[:owner_id].present?
      # Show all the documents for the owner for that entity
      @owner = params[:owner_type].constantize.find(params[:owner_id])
      @entity = @owner.entity

      @documents = if policy(@owner).show?
                     Document.where(owner_id: params[:owner_id], owner_type: params[:owner_type])
                   else
                     Document.none
                   end
    end
    @show_steps = false
  end

  # Only allow a list of trusted parameters through.
  def document_params
    params.require(:document).permit(:name, :text, :entity_id, :video, :form_type_id, :tag_list,
                                     :signature_enabled, :signed_by_id, :public_visibility, :send_email,
                                     :download, :printing, :orignal, :owner_id, :owner_type, :owner_tag,
                                     :tag_list, :folder_id, :file, properties: {}, signature_type: [])
  end
end
