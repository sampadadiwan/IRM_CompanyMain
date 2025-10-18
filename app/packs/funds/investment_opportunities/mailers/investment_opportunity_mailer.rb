class InvestmentOpportunityMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_investment_opportunity
  def set_investment_opportunity
    @investment_opportunity = InvestmentOpportunity.find(params[:investment_opportunity_id])
    email_method = params[:email_method] || @notification.params[:email_method]
    @custom_notification = @investment_opportunity.entity.custom_notification(email_method, custom_notification_id: params[:custom_notification_id], for_type: "InvestmentOpportunity")
  end

  def notify_open_for_interests
    send_mail(subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, open for interests")
  end

  def notify_allocation
    send_mail(subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, has been allocated")
  end
end
