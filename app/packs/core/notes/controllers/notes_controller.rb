class NotesController < ApplicationController
  before_action :set_note, only: %w[show update destroy edit]

  # GET /notes or /notes.json
  def index
    @q = Note.ransack(params[:q])
    if params[:q].nil? || params[:q][:s].blank?
      @q.sorts = 'on desc' # Set your default sort column and direction
    end

    @notes = policy_scope(@q.result)

    if params[:investor_id]
      if current_user.curr_role == "employee"
        # Employees can only see notes for investors they have access to
        @investor = Investor.find(params[:investor_id])
        authorize @investor, :show?
      end
      @notes = @notes.where(investor_id: params[:investor_id])
    end

    @notes = @notes.where(user_id: params[:user_id]) if params[:user_id]
    @notes = @notes.where(investor_id: params[:owner_id]) if params[:owner_id].present? && params[:owner_type] == "Investor"
    @notes = @notes.where(investor_id: params[:investor_id]) if params[:investor_id]

    @notes = NoteSearch.perform(@notes, current_user, params)
    @notes = @notes.with_all_rich_text.includes(:user, :investor).page params[:page]
    @notes = @notes.per((params[:per_page] || 10).to_i)
  end

  def search
    query = params[:query]
    if query.present?
      @notes = NoteIndex.filter(term: { entity_id: current_user.entity_id })
                        .query(query_string: { fields: NoteIndex::SEARCH_FIELDS,
                                               query:, default_operator: 'and' }).page params[:page]

      render "index"
    else
      redirect_to notes_path(request.parameters)
    end
  end

  # GET /notes/1 or /notes/1.json
  def show; end

  # GET /notes/new
  def new
    @note = Note.new(note_params)
    @note.investor_id = note_params[:owner_id] if note_params[:owner_type] == "Investor"
    @note.entity_id ||= @note.investor.entity_id
    @note.user_id ||= current_user.id
    @note.on = Time.zone.today
    @note.reminder = Reminder.new(entity_id: @note.entity_id)
    authorize @note
  end

  # GET /notes/1/edit
  def edit
    @note.build_reminder(entity_id: @note.entity_id) unless @note.reminder
  end

  # POST /notes or /notes.json
  def create
    @note = Note.new(note_params)
    @note.user_id = current_user.id
    @note.entity_id = current_user.entity_id
    if @note.reminder.email.present?
      @note.reminder.entity_id = @note.entity_id
      @note.reminder.note = "Reminder for #{@note}"
    else
      @note.reminder = nil
    end

    authorize @note

    respond_to do |format|
      if @note.save
        format.html { redirect_to note_url(@note), notice: "Note was successfully created." }
        format.json { render :show, status: :created, location: @note }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @note.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /notes/1 or /notes/1.json
  def update
    np = note_params
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
  end

  # Only allow a list of trusted parameters through.
  def note_params
    params.require(:note).permit(:details, :entity_id, :user_id, :investor_id, :on, reminder_attributes: %i[due_date email])
  end
end
