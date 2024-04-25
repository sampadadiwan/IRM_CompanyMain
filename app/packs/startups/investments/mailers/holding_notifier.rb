class HoldingNotifier < BaseNotifier
  # Add required params
  required_param :holding
  required_param :email_method

  def mailer_name(_notification = nil)
    HoldingMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      holding_id: params[:holding].id
    }
  end

  notification_methods do
    def message
      @holding = params[:holding]
      params[:msg] || "Holding: #{@holding}"
    end

    def custom_notification
      nil
    end

    def url
      holding_path(id: params[:holding].id, sub_domain: params[:holding].entity.sub_domain)
    end
  end
end
