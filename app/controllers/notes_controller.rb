class NotesController < ApplicationController
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
                                               query:, default_operator: 'and' })

      render "index"
    else
      redirect_to notes_path(request.parameters)
    end
  end

  # GET /notes/1 or /notes/1.json
  def show
    authorize @note
  end

  # GET /notes/new
  def new
    @note = Note.new(note_params)
    @note.entity_id = current_user.entity_id
    @note.on = Time.zone.today
    authorize @note
  end

  # GET /notes/1/edit
  def edit
    authorize @note
  end

  # POST /notes or /notes.json
  def create
    @note = Note.new(note_params)
    @note.user_id = current_user.id
    @note.entity_id = current_user.entity_id
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
    authorize @note
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
    authorize @note
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
  end

  # Only allow a list of trusted parameters through.
  def note_params
    params.require(:note).permit(:details, :entity_id, :user_id, :investor_id, :on)
  end
end
