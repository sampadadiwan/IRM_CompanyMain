class ReminderNotifier < BaseNotifier
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
      reminder_id: record.id
    }
  end

  notification_methods do
    def message
      @reminder = record
      params[:msg] || "Reminder: #{@reminder.note}"
    end

    def custom_notification
      nil
    end

    def url
      reminder_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
