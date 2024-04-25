class InterestNotifier < BaseNotifier
  # Add required params
  required_param :interest
  required_param :email_method

  def mailer_name(_notification = nil)
    InterestMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      interest_id: params[:interest].id
    }
  end

  notification_methods do
    def message
      @interest = params[:interest]
      params[:msg] || "Interest: #{@interest}"
    end

    def custom_notification
      nil
    end

    def url
      interest_path(id: params[:interest].id, sub_domain: params[:interest].entity.sub_domain)
    end
  end
end
