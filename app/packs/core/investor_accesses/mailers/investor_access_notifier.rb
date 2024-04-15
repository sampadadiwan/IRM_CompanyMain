class InvestorAccessNotifier < BaseNotifier
  # Add required params
  required_param :investor_access

  def mailer_name(_notification = nil)
    InvestorAccessMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      investor_access_id: params[:investor_access].id,
      entity_id: params[:entity_id]
    }
  end

  notification_methods do
    def message
      @investor_access ||= params[:investor_access]
      params[:msg] || "Access granted to #{@investor_access.entity.name}"
    end

    def custom_notification
      nil
    end

    def url
      investor_access_path(id: params[:investor_access].id)
    end
  end
end
