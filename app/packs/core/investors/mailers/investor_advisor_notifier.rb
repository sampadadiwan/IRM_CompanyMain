class InvestorAdvisorNotifier < BaseNotifier
  required_param :investor_advisor
  required_param :email_method

  def mailer_name(_notification = nil)
    InvestorAdvisorMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      investor_advisor_id: params[:investor_advisor].id,
      investor_id: params[:investor].id,
      import_upload_id: params[:import_upload].id,
      fund_name: params[:fund_name]
    }
  end

  notification_methods do
    def message
      @investor_advisor = params[:investor_advisor]
      params[:msg] || "Investor Advisor: #{@investor_advisor}"
    end

    def custom_notification
      nil
    end

    def url
      investor_advisor_path(id: params[:investor_advisor].id, sub_domain: params[:investor_advisor].entity.sub_domain)
    end
  end
end
