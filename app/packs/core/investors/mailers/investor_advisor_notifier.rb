class InvestorAdvisorNotifier < BaseNotifier
  required_param :email_method

  def mailer_name(_notification = nil)
    InvestorAdvisorMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      investor_advisor_id: record.id,
      owner_name: params[:owner_name]
    }
  end

  notification_methods do
    def message
      @investor_advisor = record
      params[:msg] || "Investor Advisor: #{@investor_advisor}"
    end

    def custom_notification
      nil
    end

    def url
      investor_advisor_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
