class NotificationsController < ApplicationController
  before_action :set_notification, only: %i[show edit update destroy mark_as_read]

  # GET /notifications or /notifications.json
  def index
    authorize Noticed::Notification
    @q = Noticed::Notification.ransack(params[:q])
    @notifications = policy_scope(@q.result)
    # Filter by entity
    @notifications = if params[:entity_id].present?
                       @notifications.joins(:event).where("JSON_UNQUOTE(JSON_EXTRACT(noticed_events.params, '$.entity_id')) = ?", params[:entity_id])
                     else
                       # Filter by user
                       @notifications.where(recipient_id: current_user.id, recipient_type: "User")
                     end
    # Get only unread notifications
    @notifications = @notifications.unread if params[:all].blank?

    # Mark all as read
    if params[:mark_as_read].present? && params[:user_id].present?
      @notifications.mark_as_read
      current_user.touch # This is to bust the topbar cache which shows new notifications
    end

    @pagy, @notifications = pagy(@notifications.includes(:event).order(id: :desc))
  end

  # GET /notifications/1 or /notifications/1.json
  def show
    if Noticed::NotificationPolicy.new(current_user, @notification).mark_as_read? && params[:debug].blank?
      ActiveRecord::Base.connected_to(role: :writing) do
        @notification.mark_as_read
      end
      redirect_to @notification.url, allow_other_host: true
    end
  end

  def mark_as_read
    params[:mark] == "read" ? @notification.mark_as_read : @notification.mark_as_unread
    respond_to do |format|
      format.html { redirect_to request.referer, notice: "Notification was successfully marked as #{params[:mark]}." }
      format.json { head :no_content }
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
    @notification = Noticed::Notification.find(params[:id])
    authorize @notification, policy_class: Noticed::NotificationPolicy
  end

  # Only allow a list of trusted parameters through.
  def notification_params
    params.require(:notification).permit(:recipient_id, :recipient_type, :type, :params, :read_at)
  end
end
