class ExcerciseNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    ExcerciseMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      excercise_id: record.id
    }
  end

  notification_methods do
    def message
      @excercise = record
      params[:msg] || "Excercise: #{@excercise}"
    end

    def custom_notification
      nil
    end

    def url
      excercise_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
