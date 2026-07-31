class NotesController < ApplicationController
  before_action :set_note, only: %w[show update destroy edit]

  # GET /notes or /notes.json
  def index
    @bread_crumbs = { Notes: notes_path }

    @q = Note.ransack(params[:q])
    if params[:q].nil? || params[:q][:s].blank?
      @q.sorts = 'on desc' # Set your default sort column and direction
    end

    @notes = policy_scope(@q.result)
    # Backward compatibility: some pages still send investor_id instead of owner_id/owner_type.
    owner_id = params[:owner_id].presence
    owner_type = params[:owner_type].presence

    if owner_id.present?
      if owner_type.present?
        owner = owner_type.safe_constantize&.find_by(id: owner_id)
        @notes = if owner.present? && policy(owner).show?
                   @notes.where(owner_id:, owner_type:)
                 else
                   @notes.none
                 end
      else
        # If owner_type is not provided, treat as Investor for legacy callers.
        owner = policy_scope(Investor).find_by(id: owner_id)
        @notes = if owner.present? && policy(owner).show?
                   @notes.where(owner_id:, owner_type: "Investor")
                 else
                   @notes.none
                 end
      end
    end
    @notes = @notes.where(user_id: params[:user_id]) if params[:user_id]
    @notes = NoteSearch.perform(@notes, current_user, params)
    @pagy, @notes = pagy(@notes.with_all_rich_text.includes(:user, :owner))
  end

  def search
    query = params[:query]
    if query.present?
      @notes = NoteIndex.filter(term: { entity_id: current_user.entity_id })
                        .query(simple_query_string: { fields: NoteIndex::SEARCH_FIELDS,
                                                      query:, default_operator: 'and' })

      @pagy, @notes = pagy(@notes.page(params[:page]))
      render "index"
    else
      redirect_to notes_path(request.parameters)
    end
  end

  # GET /notes/1 or /notes/1.json
  def show
    @bread_crumbs = { Notes: notes_path, "#{@note}": note_path(@note) }
  end

  # GET /notes/new
  def new
    # Here we have added owner_type and owner_id for the notes
    # embedded_note_context is for handling special requirements for notes in deal context
    @note = params[:note] ? Note.new(normalized_note_params) : Note.new
    @note.owner_id ||= params[:owner_id]
    @note.owner_type ||= params[:owner_type]
    @note.owner_type ||= "User" if params[:embedded_note_context].blank?
    @note.owner_type = "Investor" if @note.owner_id.present? && @note.owner_type.blank?
    @note.owner_id = current_user.id if @note.owner_type == "User"
    @note.entity_id ||= @note.owner&.entity_id
    @note.user_id ||= current_user.id
    # On should be blank by default
    @note.reminder = Reminder.new(entity_id: @note.entity_id)

    @bread_crumbs = { Notes: notes_path }
    @bread_crumbs[@note.owner.investor_name.to_s] = investor_path(@note.owner, tab: 'notes-tab') if @note.owner.is_a?(Investor)
    @bread_crumbs[:New] = nil

    authorize_note!(@note)
  end

  # GET /notes/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    @note.build_reminder(entity_id: @note.entity_id) unless @note.reminder
  end

  # POST /notes or /notes.json
  def create
    @note = Note.new(normalized_note_params)
    @note.owner_type = "Investor" if @note.owner_id.present? && @note.owner_type.blank?
    @note.user_id = current_user.id
    @note.entity_id = current_user.entity_id
    if @note.reminder.email.present?
      @note.reminder.entity_id = @note.entity_id
      @note.reminder.note = "Reminder for #{@note}"
    else
      @note.reminder = nil
    end

    authorize_note!(@note)

    respond_to do |format|
      if @note.save
        # Redirect back to the originating page (e.g. a deal) if a safe relative return_to was provided
        redirect_target = params[:return_to].presence&.then { |url| url.start_with?('/') ? url : nil } || note_url(@note)
        format.html { redirect_to redirect_target, notice: "Note was successfully created." }
        format.json { render :show, status: :created, location: @note }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @note.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /notes/1 or /notes/1.json
  def update
    np = normalized_note_params
    if params[:note] && params[:note][:reminder_attributes] && params[:note][:reminder_attributes][:email].present?
      @note.build_reminder(entity_id: @note.entity_id, note: "Reminder for #{@note}") unless @note.reminder
    else
      @note.reminder = nil
      np = np.except(:reminder_attributes)
    end

    respond_to do |format|
      if @note.update(np)
        format.html { redirect_to note_url(@note), notice: "Note was successfully updated." }
        format.json { render :show, status: :ok, location: @note }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @note.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /notes/1 or /notes/1.json
  def destroy
    @note.destroy
    respond_to do |format|
      format.html { redirect_to notes_url, notice: "Note was successfully deleted." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_note
    @note = Note.find(params[:id])
    authorize @note
    @bread_crumbs = { Notes: notes_path }
    @bread_crumbs[@note.owner.investor_name.to_s] = investor_path(@note.owner, tab: 'notes-tab') if @note.owner.is_a?(Investor)
    @bread_crumbs[@note.to_s] = note_path(@note)
  end

  # Only allow a list of trusted parameters through.
  def note_params
    params.require(:note).permit(:tags, :details, :entity_id, :user_id, :owner_id, :owner_type, :on, reminder_attributes: %i[due_date email])
  end

  def normalized_note_params
    attrs = note_params.to_h

    case params[:embedded_note_context].presence
    when "deal_tab"
      attrs["owner_type"] = "DealInvestor"
    when "deal_investor_tab"
      attrs["owner_type"] = "DealInvestor"
      locked_owner_id = params[:embedded_owner_id].presence || params[:owner_id].presence || attrs["owner_id"]
      attrs["owner_id"] = locked_owner_id if locked_owner_id.present?
    end

    attrs["owner_id"] = current_user.id if attrs["owner_type"] == "User"
    attrs
  end

  def embedded_deal_investor_context?
    params[:embedded_note_context].presence == "deal_investor_tab" || params[:from] == "deal_details"
  end

  def authorize_note!(note)
    if embedded_deal_investor_context? && note.owner.is_a?(DealInvestor)
      authorize note, :deal_note_create?
    else
      authorize note
    end
  end
end
