class DocumentsController < ApplicationController
  # prepend_view_path 'app/packs/core/documents/views'

  include ActiveStorage::SetCurrent
  include DocumentHelper
  skip_before_action :verify_authenticity_token, :set_current_entity, :authenticate_user!, :set_search_controller, :set_paper_trail_whodunnit, only: %i[signature_progress]

  before_action :set_document, only: %w[show update destroy edit send_for_esign fetch_esign_updates]
  after_action :verify_authorized, except: %i[index search investor folder signature_progress]

  after_action :verify_policy_scoped, only: []
  # skip_before_action :authenticate_user!, :only => [:show]

  impressionist actions: [:show]

  def signature_progress
    # Check response  - if contains proper info then update doc esign status
    # if not then just respond with 200 OK
    update_signature_progress(params)
    # Always respond with 200 OK - Expected from Digio
    render json: "Ok", status: :ok
  end

  def fetch_esign_updates
    DocumentEsignUpdateJob.new.perform(@document.id)
    redirect_to document_url(@document), notice: "Fetching Updates for E-Signatures"
  end

  # GET /documents or /documents.json
  def index
    if params[:owner_id].present? && params[:owner_type].present?
      # This is typicaly for investors to view documents of a sale, offer, commitment etc
      owner_documents
    else
      # See your own docs
      @entity = current_user.entity
      @documents = policy_scope(Document)
      authorize(Document)
    end
    # Filter by owner_tag
    @documents = @documents.where(owner_tag: params[:owner_tag]) if params[:owner_tag].present?
    # This is specifically for non company_admins
    @documents = @documents.where(user_id: current_user.id) unless current_user.has_cached_role?(:company_admin)

    # Newest docs first
    @documents = @documents.includes(:folder).order(id: :desc)
  end

  def folder
    if params[:folder_id].present?
      @folder = Folder.find(params[:folder_id])
      @entity = @folder.entity

      if @folder.entity_id == current_user.entity_id
        @documents = policy_scope(Document)
      else
        # Ensure that the IA user has access to the folder, as IAs can only access certain funds/deals etc
        authorize(@folder, :show?) || authorize(@folder&.owner, :show?)
        @documents = Document.for_investor(current_user, @folder.entity)
      end

      if params[:no_folders].present?
        @documents = @documents.where(folder_id: params[:folder_id])
      else
        @documents = @documents.joins(:folder).merge(Folder.descendants_of(params[:folder_id]))
        @documents = @documents.or(Document.where(folder_id: params[:folder_id]))
      end
      # Newest docs first
      @documents = @documents.includes(:folder).order(id: :desc)

    else
      # Newest docs first
      @documents = Document.none
    end

    @no_folders = false
    render "index"
  end

  def investor
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

  def send_for_esign
    if @document.send_for_esign(force: params[:force])
      redirect_to document_url(@document), notice: "Document was queued for e-signature."
    else
      redirect_to document_url(@document, display_status: true), alert: "Document was NOT sent for e-signature."
    end
  end

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
    @documents = Document.entity_documents(current_user, @entity.id)
  end

  def owner_documents
    # We are trying to get documents that belong to some entity
    @owner = nil
    if params[:owner_type].present? && params[:owner_id].present?
      # Show all the documents for the owner for that entity
      @owner = params[:owner_type].constantize.find(params[:owner_id])
      @entity = @owner.entity

      @documents = if policy(@owner).show?
                     Document.owner_documents(@owner)
                   else
                     Document.none
                   end
    end
    @show_steps = false
  end

  # Only allow a list of trusted parameters through.
  def document_params
    params.require(:document).permit(:name, :text, :entity_id, :video, :form_type_id, :tag_list, :template,
                                     :signature_enabled, :public_visibility, :send_email, :display_on_page,
                                     :download, :printing, :orignal, :owner_id, :owner_type, :owner_tag,
                                     :tag_list, :folder_id, :file, properties: {},  e_signatures_attributes: %i[id user_id label signature_type notes _destroy])
  end
end
