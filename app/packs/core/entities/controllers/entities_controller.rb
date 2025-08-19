class EntitiesController < ApplicationController
  before_action :set_entity, only: %w[show update destroy edit report kpi_reminder]
  after_action :verify_authorized, except: %i[dashboard search index investor_entities delete_attachment]

  # GET /entities or /entities.json
  def index
    @entities = policy_scope(Entity)
    render "index", locals: { vc_view: false }
  end

  def dashboard
    @dashboard = current_user.custom_dashboard
    redirect_to @dashboard if @dashboard.present?
  end

  def report
    render "entities/#{params[:report]}"
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

  def merge
    if request.get?
      authorize Entity, :merge?
      render "merge"
    else
      defunct_entity = Entity.find(params[:old_entity_id])
      authorize defunct_entity, :merge?

      retained_entity = Entity.find(params[:new_entity_id])
      authorize retained_entity, :merge?

      Entity.merge_investor_entity(defunct_entity, retained_entity)
      redirect_to entity_url(new_entity), notice: "Entity Merge Completed"
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

  def kpi_reminder
    EntityMailer.with(entity_id: @entity.id, requesting_entity_id: current_user.entity_id).kpi_reminder.deliver_later
    redirect_path = request.referer || kpi_reports_path
    redirect_to redirect_path, notice: "Reminder sent"
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
                                   :funding_amount, :funding_unit, :details, :logo_url, :primary_email,
                                   :investor_categories, :instrument_types, :sub_domain, :enable_support,
                                   :currency, :units, :logo, permissions: [], entity_setting_attributes: [:id, :mailbox, :individual_kyc_doc_list, :non_individual_kyc_doc_list, :sandbox, :sandbox_emails, :cc, :sandbox_numbers, :kyc_docs_note, :entity_bcc, :kyc_bank_account_types, { custom_flags: [], kpi_doc_list: [] }])
  end
end
