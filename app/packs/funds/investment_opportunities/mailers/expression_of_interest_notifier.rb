class ExpressionOfInterestNotifier < BaseNotifier
  # Add required params
  required_param :expression_of_interest

  def mailer_name(_notification = nil)
    ExpressionOfInterestMailer
  end

  def email_method(_notification = nil)
    :notify_approved
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      expression_of_interest_id: params[:expression_of_interest].id
    }
  end

  notification_methods do
    def message
      @expression_of_interest = params[:expression_of_interest]
      params[:msg] || "Expression Of Interest Approved: #{@expression_of_interest.investment_opportunity.company_name}"
    end

    def url
      expression_of_interest_path(id: params[:expression_of_interest].id)
    end
  end
end
