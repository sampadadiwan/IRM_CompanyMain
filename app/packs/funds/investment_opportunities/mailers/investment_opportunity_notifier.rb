class InvestmentOpportunityNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    InvestmentOpportunityMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      investment_opportunity_id: record.id,
      from_email: record.custom_fields.from_email
    }
  end

  notification_methods do
    def message
      @investment_opportunity = record
      params[:msg] || "Investment Opportunity: #{@investment_opportunity&.name}"
    end

    def custom_notification
      nil
    end

    def url
      investment_opportunity_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
