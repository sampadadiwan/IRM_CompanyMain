class NotificationsController < ApplicationController
  before_action :set_notification, only: %i[show edit update destroy mark_as_read]

  # GET /notifications or /notifications.json
  def index
    @notifications = policy_scope(Notification).newest_first.page(params[:page])
    @notifications = @notifications.unread if params[:all].blank?
    if params[:mark_as_read].present?
      @notifications.mark_as_read!
      current_user.touch # This is to bust the topbar cache which shows new notifications
    end
  end

  # GET /notifications/1 or /notifications/1.json
  def show
    @notification.mark_as_read!
    redirect_to @notification.to_notification.url
  end

  def mark_as_read
    params[:mark] == "read" ? @notification.mark_as_read! : @notification.mark_as_unread!
    respond_to do |format|
      format.html { redirect_to notifications_url, notice: "Notification was successfully marked as #{params[:mark]}." }
      format.json { head :no_content }
    end
  end

  # GET /notifications/new
  def new
    @notification = Notification.new
  end

  # GET /notifications/1/edit
  def edit; end

  # POST /notifications or /notifications.json
  def create
    @notification = Notification.new(notification_params)

    respond_to do |format|
      if @notification.save
        format.html { redirect_to notification_url(@notification), notice: "Notification was successfully created." }
        format.json { render :show, status: :created, location: @notification }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @notification.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /notifications/1 or /notifications/1.json
  def update
    respond_to do |format|
      if @notification.update(notification_params)
        format.html { redirect_to notification_url(@notification), notice: "Notification was successfully updated." }
        format.json { render :show, status: :ok, location: @notification }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @notification.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /notifications/1 or /notifications/1.json
  def destroy
    @notification.destroy

    respond_to do |format|
      format.html { redirect_to notifications_url, notice: "Notification was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_notification
    @notification = Notification.find(params[:id])
    authorize @notification
  end

  # Only allow a list of trusted parameters through.
  def notification_params
    params.require(:notification).permit(:recipient_id, :recipient_type, :type, :params, :read_at)
  end
end
