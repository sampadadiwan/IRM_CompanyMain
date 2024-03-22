class ExcerciseNotifier < BaseNotifier
  # Add required params
  required_param :excercise
  required_param :email_method

  def mailer_name(_notification = nil)
    ExcerciseMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      excercise_id: params[:excercise].id
    }
  end

  notification_methods do
    def message
      @excercise = params[:excercise]
      params[:msg] || "Excercise: #{@excercise}"
    end

    def url
      excercise_path(id: params[:excercise].id)
    end
  end
end
