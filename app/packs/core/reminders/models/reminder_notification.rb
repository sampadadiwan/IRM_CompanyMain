class ReminderNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "ReminderMailer", method: :send_reminder, format: :email_data

  # Add required params
  param :reminder

  def email_data
    {
      user_id: recipient.id,
      reminder_id: params[:reminder].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @reminder = params[:reminder]
    params[:msg] || "Reminder: #{@reminder.note}"
  end

  def url
    reminder_path(id: params[:reminder].id)
  end
end
