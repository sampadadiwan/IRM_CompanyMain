class InvestorAccessesController < ApplicationController
  before_action :set_investor_access, only: %i[show edit update destroy approve]
  after_action :verify_authorized, except: %i[index search]

  # GET /investor_accesses or /investor_accesses.json
  def index
    authorize(InvestorAccess)
    if params[:investor_id].present?
      @investor = Investor.find(params[:investor_id])
      @bread_crumbs = { Investors: investors_path, @investor.investor_name => investor_path(@investor), Access: nil }
    else
      @bread_crumbs = { 'Investor Access': investor_accesses_path }
    end

    @q = InvestorAccess.ransack(params[:q])
    @investor_accesses = policy_scope(@q.result).includes(:investor, :user, :granter)
    @investor_accesses = InvestorAccessSearch.perform(@investor_accesses, current_user, params)
    @investor_accesses = @investor_accesses.where(approved: params[:approved]) if params[:approved].present?
    @investor_accesses = @investor_accesses.where(investor_id: params[:investor_id]) if params[:investor_id].present?
    @investor_accesses = @investor_accesses.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @pagy, @investor_accesses = pagy(@investor_accesses) if params[:all].blank?
  end

  def search
    authorize(InvestorAccess)
    @bread_crumbs = { 'Investor Access': investor_accesses_path }
    @entity = current_user.entity
    query = params[:query]
    if query.present?

      InvestorAccessIndex.filter(term: { entity_id: @entity.id })
                         .query(simple_query_string: { fields: InvestorAccessIndex::SEARCH_FIELDS,
                                                       query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to investor_accesses_path
    end
  end

  def request_access
    @investor_access = InvestorAccess.new(investor_access_params)
    @investor_access.user_id = current_user.id
    @investor_access.email = current_user.email
    @investor_access.first_name = current_user.first_name
    @investor_access.last_name = current_user.last_name
    @investor_access.entity_id = @investor_access.investor.entity_id
    @investor_access.approved = false
    authorize @investor_access

    respond_to do |format|
      if @investor_access.save
        format.html { redirect_to entity_path(@investor_access.entity), notice: "Investor access request successfull. You will be notified when your request is approved." }
        format.json { render :show, status: :created, location: @investor_access }
      else
        format.html { redirect_to entity_path(@investor_access.entity), notice: "Investor access request failed. #{@investor_access.errors.full_messages}" }
        format.json { render json: @investor_access.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /investor_accesses/1 or /investor_accesses/1.json
  def show
    # Checked against the user's live role rather than InvestorAccess#is_investor_advisor, since
    # that cached flag is only recomputed on save and can be stale relative to the user's roles.
    return unless @investor_access.user&.has_cached_role?(:investor_advisor)

    # Fund-level access rights the investor granted this advisor when they were set up as an
    # investor_advisor (see AddFolioInvestorAdvisor#create_access_rights). entity_id here is the
    # investor's own firm (investor_entity_id), which is how those grants are scoped.
    @advisor_access_rights = AccessRight.where(
      user_id: @investor_access.user_id,
      entity_id: @investor_access.investor_entity_id,
      owner_type: "Fund",
      metadata: "investor_advisor"
    ).includes(:owner, :granted_by)
  end

  # GET /investor_accesses/new
  def new
    @investor_access = InvestorAccess.new(investor_access_params)
    @investor_access.approved = true

    authorize @investor_access

    # LP CRM: entity_id is normally only set in create (from the investor), but
    # setup_custom_fields needs it now to find the entity's "InvestorAccess" form
    # type — without it the contact custom fields would not render on the new form.
    @investor_access.entity_id ||= @investor_access.investor&.entity_id
    setup_custom_fields(@investor_access)

    if @investor_access.investor_id.present?
      @investor = @investor_access.investor
      @bread_crumbs = { Investors: investors_path, @investor.investor_name => investor_path(@investor), Access: investor_accesses_path(investor_id: @investor.id), New: nil }
    else
      @bread_crumbs = { 'Investor Access': investor_accesses_path, New: nil }
    end
  end

  # GET /investor_accesses/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    # LP CRM: existing rows created before the form type existed have a nil
    # form_type_id; resolve it so the contact custom fields render on edit too.
    setup_custom_fields(@investor_access)
  end

  def approve
    @investor_access.approved = !@investor_access.approved
    @investor_access.granted_by = current_user.id
    @investor_access.save
    msg = if @investor_access.approved
            "Approved #{@investor_access.email}."
          else
            "Un-approved #{@investor_access.email}."
          end
    UserAlert.new(user_id: current_user.id, message: msg, level: "success").broadcast

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("investor_access_#{@investor_access.id}",
                               partial: "investor_accesses/investor_access", locals: { investor_access: @investor_access, investor_id: params[:investor_id] })
        ]
      end
      format.html { redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully approved." }
      format.json { @investor_access.to_json }
    end
  end

  def upload
    authorize(InvestorAccess)
    @bread_crumbs = { 'Investor Access': investor_accesses_path, Upload: nil }
  end

  # POST /investor_accesses or /investor_accesses.json
  def create
    @investor_access = InvestorAccess.new(investor_access_params)
    @investor_access.entity_id = @investor_access.investor.entity_id
    @investor_access.granted_by = current_user.id
    # Only this UI "add investor access" action blocks investor_advisor users; other creation
    # paths (CSV import, self-service request_access, admin panel) do not set this flag.
    @investor_access.disallow_investor_advisor = true

    authorize @investor_access

    respond_to do |format|
      if @investor_access.save
        format.turbo_stream do
          UserAlert.new(user_id: current_user.id, message: "Added #{@investor_access.email} to investor users", level: "success").broadcast
          render :create
        end
        format.html { redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully created." }
        format.json { render :show, status: :created, location: @investor_access }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_access.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_accesses/1 or /investor_accesses/1.json
  def update
    authorize @investor_access

    respond_to do |format|
      # SECURITY (finding M6): the record is authorized BEFORE assignment, so strip the identity/
      # scoping fields to stop a grant being retargeted to another tenant, investor, or user after
      # the check. entity_id/investor_id/user_id are fixed at creation; the user is re-derived from
      # email by InvestorAccess#update_user, and approved/email/tags remain editable.
      if @investor_access.update(investor_access_params.except(:entity_id, :investor_id, :user_id))
        # Turbo sends the turbo-stream Accept header on every form submission, so
        # this branch is also reached by the standalone /edit page (opened from the
        # show page) — where the stream's targets (the list row and the
        # new_investor_access frame) do not exist. Only the inline list/tab form
        # (which carries the inline_frame marker, see _form) gets the stream; the
        # standalone edit redirects back to the show page.
        format.turbo_stream do
          UserAlert.new(user_id: current_user.id, message: "Updated #{@investor_access.email}", level: "success").broadcast
          if params[:inline_frame].present?
            render :update
          else
            redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully updated."
          end
        end
        format.html { redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_access }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_access.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_accesses/1 or /investor_accesses/1.json
  def destroy
    @investor_access.destroy

    respond_to do |format|
      format.turbo_stream do
        UserAlert.new(user_id: current_user.id, message: "Destroyed #{@investor_access.email}", level: "info").broadcast

        render turbo_stream: [
          turbo_stream.remove(@investor_access)
        ]
      end
      format.html { redirect_to investor_accesses_path, notice: "Investor access was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_access
    @investor_access = InvestorAccess.includes(:user, :investor).find(params[:id])
    authorize @investor_access
    @bread_crumbs = {
      Investors: investors_path,
      @investor_access.investor.investor_name => investor_path(@investor_access.investor),
      User: investor_accesses_path(investor_id: @investor_access.investor_id),
      @investor_access.email => investor_access_path(@investor_access)
    }
  end

  # Only allow a list of trusted parameters through.
  def investor_access_params
    # form_type_id + properties: LP CRM — tenant-configured contact custom fields
    # (designation, POC role, intro, ...) via WithCustomField, same pattern as Task.
    # Changed: Added :exempt_from_nda to permitted params.
    # Why: Stakeholder-level NDA exemption checkbox on the InvestorAccess form.
    params.require(:investor_access).permit(:investor_id, :user_id, :email, :cc, :approved,
                                            :phone, :whatsapp_enabled, :granted_by, :entity_id, :first_name, :last_name, :call_code, :email_enabled, :tag_list,
                                            :exempt_from_nda, :form_type_id, properties: {})
  end
end
