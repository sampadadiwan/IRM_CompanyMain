class NotesController < ApplicationController
  # prepend_view_path 'app/packs/core/notes/views'
  before_action :set_note, only: %w[show update destroy edit]

  # GET /notes or /notes.json
  def index
    @notes = policy_scope(Note)

    @notes = @notes.where(investor_id: params[:investor_id]) if params[:investor_id]
    @notes = @notes.where(user_id: params[:user_id]) if params[:user_id]

    @notes = @notes.with_all_rich_text.includes(:user, :investor)
                   .order("notes.id desc").page params[:page]
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
    @note.entity_id = current_user.entity_id
    @note.on = Time.zone.today
    @note.reminder = Reminder.new(entity_id: @note.entity_id, due_date: Time.zone.today + 1.week, email: current_user.email)
    authorize @note
  end

  # GET /notes/1/edit
  def edit
    @note.build_reminder(entity_id: @note.entity_id, due_date: Time.zone.today + 1.week, email: current_user.email) unless @note.reminder
  end

  # POST /notes or /notes.json
  def create
    @note = Note.new(note_params)
    @note.user_id = current_user.id
    @note.entity_id = current_user.entity_id
    if @note.reminder
      @note.reminder.entity_id = @note.entity_id
      @note.reminder.note = "Reminder for #{@note}"
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
    respond_to do |format|
      if @note.update(note_params)
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
