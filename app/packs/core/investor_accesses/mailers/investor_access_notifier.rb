class InvestorAccessNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    InvestorAccessMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      investor_access_id: record.id,
      investor_id: record.investor_id,
      entity_id: params[:entity_id]
    }
  end

  notification_methods do
    def message
      @investor_access ||= record
      params[:msg] || "Access granted to #{@investor_access&.entity&.name}"
    end

    def custom_notification
      nil
    end

    def url
      investor_access_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
