class SecondarySaleNotifier < BaseNotifier
  # Add required params
  required_param :secondary_sale
  required_param :email_method

  def mailer_name(_notification = nil)
    SecondarySaleMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      secondary_sale_id: params[:secondary_sale].id
    }
  end

  notification_methods do
    def message
      @secondary_sale ||= params[:secondary_sale]
      @custom_notification ||= custom_notification
      @custom_notification&.subject.presence || params[:msg].presence || "SecondarySale: #{@secondary_sale}"
    end

    def custom_notification
      @secondary_sale ||= params[:secondary_sale]
      @custom_notification ||= @secondary_sale.custom_notification(params[:email_method])
      @custom_notification
    end

    def url
      secondary_sale_path(id: params[:secondary_sale].id)
    end
  end
end
