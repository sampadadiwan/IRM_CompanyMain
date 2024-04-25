class OfferNotifier < BaseNotifier
  # Add required params
  required_param :offer
  required_param :email_method

  def mailer_name(_notification = nil)
    OfferMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      offer_id: params[:offer].id
    }
  end

  notification_methods do
    def message
      @offer = params[:offer]
      params[:msg] || "Offer: #{@offer}"
    end

    def custom_notification
      nil
    end

    def url
      offer_path(id: params[:offer].id, sub_domain: params[:offer].entity.sub_domain)
    end
  end
end
