class InvestmentOpportunityMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_open_for_interests
    @investment_opportunity = InvestmentOpportunity.find(params[:investment_opportunity_id])

    send_mail(subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, open for interests")
  end

  def notify_allocation
    @investment_opportunity = InvestmentOpportunity.find(params[:investment_opportunity_id])

    send_mail(subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, has been allocated")
  end
end
