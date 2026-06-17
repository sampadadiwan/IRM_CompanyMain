class EntitiesController < ApplicationController
  before_action :set_entity, only: %w[show update destroy edit report kpi_reminder db_dump]
  after_action :verify_authorized, except: %i[dashboard search index investor_entities delete_attachment]

  # GET /entities or /entities.json
  def index
    @bread_crumbs = { Entities: entities_path }
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
      @entities = EntityIndex.query(simple_query_string: { fields: %i[name entity_type category],
                                                           query:, default_operator: 'and' }).objects
    end

    render "index", locals: { vc_view: true }
  end

  # GET /entities/1 or /entities/1.json
  def show
    @bread_crumbs = { Entities: entities_path, "#{@entity.name}": entity_path(@entity) }
  end

  # GET /entities/new
  def new
    @bread_crumbs = { Entities: entities_path, New: nil }
  end

  # GET /entities/1/edit
  def edit
    @bread_crumbs = { Entities: entities_path, "#{@entity.name}": entity_path(@entity), Edit: nil }
  end

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

  def db_dump
    # Trigger an adhoc DB dump. The job will still respect frequency settings
    # (e.g., skip if a daily dump was already taken) unless forced otherwise.
    EntityDbDumpJob.perform_later(entity_id: @entity.id, user_id: current_user.id, adhoc: true)
    redirect_to entity_path(@entity), notice: "Database dump generation started. You will be notified when it is ready."
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
    params.require(:entity).permit(:name, :url, :category, :founded, :entity_type, :pan, :custom_css,
                                   :funding_amount, :funding_unit, :details, :logo_url, :primary_email,
                                   :investor_categories, :instrument_types, :sub_domain, :enable_support,
                                   :currency, :units, :logo, permissions: [], entity_setting_attributes: [:id, :mailbox, :individual_kyc_doc_list, :non_individual_kyc_doc_list, :sandbox, :sandbox_emails, :cc, :sandbox_numbers, :kyc_docs_note, :kyc_doc_first_wizard, :entity_bcc, :kyc_bank_account_types, :db_dumps_enable, :db_dumps_retention_period, :db_dumps_email_enabled, :db_dumps_frequency, :db_dumps_interval, :db_dumps_custom_days, :document_colors, :mcp_enabled, :mcp_allowed_roles, :mcp_allowed_clients, :cs_judge_enabled, :cs_judge_model, { custom_flags: [], kpi_doc_list: [], mcp_allowed_roles_list: [], mcp_allowed_clients_list: [] }])
  end
end
