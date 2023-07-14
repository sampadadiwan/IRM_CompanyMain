class EntitiesController < ApplicationController
  # prepend_view_path 'app/packs/core/entities/views'
  before_action :set_entity, only: %w[show update destroy edit]
  after_action :verify_authorized, except: %i[dashboard search index investor_entities delete_attachment]

  # GET /entities or /entities.json
  def index
    @entities = policy_scope(Entity)
    render "index", locals: { vc_view: false }
  end

  def dashboard
    @entities = Entity.all
  end

  def investor_entities
    @entities = Entity.for_investor(current_user)
    render "index", locals: { vc_view: true }
  end

  def search
    query = params[:query].presence || params[:term]
    if query.present?
      query += "*"
      @entities = EntityIndex.query(query_string: { fields: %i[name entity_type category],
                                                    query:, default_operator: 'and' }).objects
    end

    render "index", locals: { vc_view: true }
  end

  # GET /entities/1 or /entities/1.json
  def show; end

  # GET /entities/new
  def new; end

  # GET /entities/1/edit
  def edit; end

  # POST /entities or /entities.json
  def create
    @entity = Entity.new(entity_params)
    @entity.created_by = current_user.id
    authorize @entity

    respond_to do |format|
      if @entity.save
        format.html { redirect_to entity_url(@entity), notice: "Entity was successfully created." }
        format.json { render :show, status: :created, location: @entity }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @entity.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /entities/1 or /entities/1.json
  def update
    respond_to do |format|
      if @entity.update(entity_params)
        format.html { redirect_to entity_url(@entity), notice: "Entity was successfully updated." }
        format.json { render :show, status: :ok, location: @entity }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @entity.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /entities/1 or /entities/1.json
  def destroy
    @entity.destroy

    respond_to do |format|
      format.html { redirect_to entities_url, notice: "Entity was successfully deleted." }
      format.json { head :no_content }
    end
  end

  # Special method to delete attachments for any model
  def delete_attachment
    attachment = ActiveStorage::Attachment.where(id: params[:attachment_id]).first
    record = attachment.record
    if policy(record).update?
      attachment.purge_later
      redirect_to record, notice: "Attachment Deleted"
    else
      redirect_to record, notice: "Attachment Deletion Failed: Access Denied"
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_entity
    @entity = Entity.find(params[:id])
    authorize @entity
  end

  # Only allow a list of trusted parameters through.
  def entity_params
    params.require(:entity).permit(:name, :url, :category, :founded, :entity_type, :pan,
                                   :funding_amount, :funding_unit, :details, :logo_url,
                                   :investor_categories, :instrument_types, :sub_domain, :enable_support,
                                   :currency, :units, :logo, entity_setting_attributes: [:id, :individual_kyc_doc_list, :non_individual_kyc_doc_list, :sandbox, :sandbox_emails, :cc, :sandbox_numbers, :kyc_docs_note, :entity_bcc, { kpi_doc_list: [] }])
  end
end
