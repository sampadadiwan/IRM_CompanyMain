class InterestNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    InterestMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      interest_id: record.id,
      investor_id: record.investor_id,
      custom_notification_id: params[:custom_notification_id]
    }
  end

  notification_methods do
    def message
      @interest = record
      @custom_notification ||= custom_notification
      params[:msg] || "Interest: #{@interest}"
    end

    def custom_notification
      @custom_notification = (CustomNotification.find(params[:custom_notification_id]) if params[:custom_notification_id].present?)
      @custom_notification
    end

    def url
      interest_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
