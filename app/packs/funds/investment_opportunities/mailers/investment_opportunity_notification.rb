# To deliver this notification:
#
# InvestmentOpportunityNotification.with(investment_opportunity_id: @investment_opportunity.id, msg: "Please View").deliver_later(current_user)
# InvestmentOpportunityNotification.with(investment_opportunity_id: @investment_opportunity.id, msg: "Please View").deliver(current_user)

class InvestmentOpportunityNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "InvestmentOpportunityMailer", method: :email_method, format: :email_data

  # Add required params
  param :investment_opportunity_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      investment_opportunity_id: params[:investment_opportunity_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investment_opportunity = InvestmentOpportunity.find(params[:investment_opportunity_id])
    params[:msg] || "Investment Opportunity: #{@investment_opportunity.name}"
  end

  def url
    investment_opportunity_path(id: params[:investment_opportunity_id])
  end
end
