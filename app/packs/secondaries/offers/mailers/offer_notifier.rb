class OfferNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    OfferMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      offer_id: record.id,
      investor_id: record.investor_id,
      custom_notification_id: params[:custom_notification_id]
    }
  end

  notification_methods do
    def message
      @offer = record
      @custom_notification ||= custom_notification
      params[:msg] || "Offer: #{@offer}"
    end

    def custom_notification
      @custom_notification = (CustomNotification.find(params[:custom_notification_id]) if params[:custom_notification_id].present?)
      @custom_notification
    end

    def url
      offer_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
