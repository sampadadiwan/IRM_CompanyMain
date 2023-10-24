class InvestmentOpportunityNotification < BaseNotification
  # Add required params
  param :investment_opportunity
  param :email_method

  def mailer_name
    InvestmentOpportunityMailer
  end

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      investment_opportunity_id: params[:investment_opportunity].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investment_opportunity = params[:investment_opportunity]
    params[:msg] || "Investment Opportunity: #{@investment_opportunity.name}"
  end

  def url
    investment_opportunity_path(id: params[:investment_opportunity].id)
  end
end
