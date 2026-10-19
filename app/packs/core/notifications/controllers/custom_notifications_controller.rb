class CustomNotificationsController < ApplicationController
  before_action :set_custom_notification, only: %i[show edit update destroy]
  # Editing an investor email invalidates the journey's review tasks (capital call and distribution journeys)
  before_action -> { @journey_started_at = Time.current }, only: %i[create update destroy]
  after_action :invalidate_journey_reviews, only: %i[create update destroy]

  # GET /custom_notifications or /custom_notifications.json
  def index
    @q = CustomNotification.ransack(params[:q])
    @custom_notifications = policy_scope(@q.result)
    @custom_notifications = with_owner_access(@custom_notifications)

    @owner = params[:q][:owner_type_eq].constantize.find(params[:q][:owner_id_eq]) if params[:q] && params[:q][:owner_id_eq] && params[:q][:owner_type_eq]

    @pagy, @custom_notifications = pagy(@custom_notifications)
  end

  # GET /custom_notifications/1 or /custom_notifications/1.json
  def show; end

  # GET /custom_notifications/new
  def new
    @custom_notification = CustomNotification.new(custom_notification_params)
    @custom_notification.owner ||= current_user.entity
    authorize @custom_notification
  end

  # GET /custom_notifications/1/edit
  def edit; end

  # POST /custom_notifications or /custom_notifications.json
  def create
    @custom_notification = CustomNotification.new(custom_notification_params)
    @custom_notification.owner ||= current_user.entity
    authorize @custom_notification

    respond_to do |format|
      if @custom_notification.save
        format.html { redirect_to custom_notification_url(@custom_notification), notice: "Custom notification was successfully created." }
        format.json { render :show, status: :created, location: @custom_notification }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @custom_notification.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /custom_notifications/1 or /custom_notifications/1.json
  def update
    respond_to do |format|
      if @custom_notification.update(custom_notification_params)
        format.html { redirect_to custom_notification_url(@custom_notification), notice: "Custom notification was successfully updated." }
        format.json { render :show, status: :ok, location: @custom_notification }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @custom_notification.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /custom_notifications/1 or /custom_notifications/1.json
  def destroy
    @custom_notification.destroy!

    respond_to do |format|
      format.html { redirect_to custom_notifications_url, notice: "Custom notification was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_custom_notification
    @custom_notification = CustomNotification.find(params[:id])
    authorize @custom_notification
    @bread_crumbs = { "#{@custom_notification.owner_type}": polymorphic_path(@custom_notification.owner),
                      "#{@custom_notification}": nil }
  end

  # Only allow a list of trusted parameters through.
  def custom_notification_params
    # E: the policy lists the fields this user may send (only support may send is_erb)
    params.require(:custom_notification).permit(policy(CustomNotification).permitted_attributes)
  end

  # Only after a successful change (the actions redirect on success)
  # Worked examples E12, E24 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # Worked examples E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def invalidate_journey_reviews
    return unless response.redirect? && @custom_notification

    JourneyEmailEdit.call(notification: @custom_notification, actor: current_user, started_at: @journey_started_at)
  end
end
