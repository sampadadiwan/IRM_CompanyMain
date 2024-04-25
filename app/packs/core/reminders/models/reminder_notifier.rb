class ReminderNotifier < BaseNotifier
  # Add required params
  required_param :reminder

  def mailer_name(_notification = nil)
    InvestorKycMailer
  end

  def email_method(_notification = nil)
    :send_reminder
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      reminder_id: params[:reminder].id
    }
  end

  notification_methods do
    def message
      @reminder = params[:reminder]
      params[:msg] || "Reminder: #{@reminder.note}"
    end

    def custom_notification
      nil
    end

    def url
      reminder_path(id: params[:reminder].id, sub_domain: params[:reminder].entity.sub_domain)
    end
  end
end
