class ReminderNotification < BaseNotification
  # Add required params
  param :reminder

  def mailer_name
    InvestorKycMailer
  end

  def email_method
    :send_reminder
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
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
