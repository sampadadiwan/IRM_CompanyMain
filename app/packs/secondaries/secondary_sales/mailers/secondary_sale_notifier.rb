class SecondarySaleNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    SecondarySaleMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      secondary_sale_id: record.id,
      investor_id: params[:investor_id],
      custom_notification_id: params[:custom_notification_id]
    }
  end

  notification_methods do
    def message
      @secondary_sale ||= record
      @custom_notification ||= custom_notification
      @custom_notification&.subject.presence || params[:msg].presence || "SecondarySale: #{@secondary_sale}"
    end

    def custom_notification
      if params[:custom_notification_id].present?
        @custom_notification = CustomNotification.find(params[:custom_notification_id])
      else
        @secondary_sale ||= record
        @custom_notification ||= @secondary_sale.custom_notification(params[:email_method])
      end
      @custom_notification
    end

    def url
      secondary_sale_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
