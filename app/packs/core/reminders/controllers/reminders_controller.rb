class RemindersController < ApplicationController
  # prepend_view_path 'app/packs/core/reminders/views'
  before_action :set_reminder, only: %i[show edit update destroy]

  # GET /reminders or /reminders.json
  def index
    @reminders = policy_scope(Reminder)
    @reminders = @reminders.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @reminders = @reminders.where(owner_type: params[:owner_type]) if params[:owner_type].present?

    @reminders = @reminders.where(sent: params[:sent] == "true") if params[:sent].present?

    @reminders = @reminders.order("reminders.due_date desc")
  end

  # GET /reminders/1 or /reminders/1.json
  def show; end

  # GET /reminders/new
  def new
    @reminder = Reminder.new(reminder_params)
    @reminder.entity_id = current_user.entity_id
    @reminder.due_date = Time.zone.today + 7.days
    @reminder.email = current_user.email

    authorize @reminder
  end

  # GET /reminders/1/edit
  def edit; end

  # POST /reminders or /reminders.json
  def create
    @reminder = Reminder.new(reminder_params)
    @reminder.entity_id = current_user.entity_id
    authorize @reminder

    respond_to do |format|
      if @reminder.save
        format.turbo_stream { render :create }
        format.html { redirect_to reminder_url(@reminder), notice: "Reminder was successfully created." }
        format.json { render :show, status: :created, location: @reminder }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @reminder.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /reminders/1 or /reminders/1.json
  def update
    respond_to do |format|
      if @reminder.update(reminder_params)
        format.turbo_stream { render :update }
        format.html { redirect_to reminder_url(@reminder), notice: "Reminder was successfully updated." }
        format.json { render :show, status: :ok, location: @reminder }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @reminder.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /reminders/1 or /reminders/1.json
  def destroy
    @reminder.destroy

    respond_to do |format|
      format.html { redirect_to reminders_url, notice: "Reminder was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_reminder
    @reminder = Reminder.find(params[:id])
    authorize(@reminder)
  end

  # Only allow a list of trusted parameters through.
  def reminder_params
    params.require(:reminder).permit(:entity_id, :owner_id, :owner_type, :note, :email, :due_date, :sent)
  end
end
