class ExpressionOfInterestNotification < BaseNotification
  # Add required params
  param :expression_of_interest

  def mailer_name
    ExpressionOfInterestMailer
  end

  def email_method
    :notify_approved
  end

  def email_data
    {
      notification_id: record.id,
      user_id: recipient.id,
      entity_id: params[:entity_id],
      expression_of_interest_id: params[:expression_of_interest].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @expression_of_interest = params[:expression_of_interest]
    params[:msg] || "Expression Of Interest Approved: #{@expression_of_interest.investment_opportunity.company_name}"
  end

  def url
    expression_of_interest_path(id: params[:expression_of_interest].id)
  end
end
