# To deliver this notification:
#
# ReminderNotification.with(reminder_id: @reminder.id, msg: "Please View").deliver_later(current_user)
# ReminderNotification.with(reminder_id: @reminder.id, msg: "Please View").deliver(current_user)

class ReminderNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "ReminderMailer", method: :send_reminder, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :reminder_id

  def email_data
    {
      user_id: recipient.id,
      reminder_id: params[:reminder_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @reminder = Reminder.find(params[:reminder_id])
    params[:msg] || "Reminder: #{@reminder.note}"
  end

  def url
    reminder_path(id: params[:reminder_id])
  end
end
